import Foundation
import Speech
import AVFoundation

@MainActor
final class VoiceSymptomViewModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    @Published var messages: [SymptomChatMessage] = []
    @Published var symptoms: [String] = []
    @Published var isListening = false
    @Published var isAssistantSpeaking = false
    @Published var aiStatus = "Hazır"
    @Published var recommendedClinic = ""
    @Published var recommendedDoctors: [DoctorResponse] = []

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private let synthesizer = AVSpeechSynthesizer()
    private var shouldOpenMicAfterSpeech = false
    private var isFinished = false

    private var lastRecognizedText = ""
    private var silenceTask: Task<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func start() {
        requestPermissions()

        guard messages.isEmpty else { return }

        let text = "Merhaba! Ben sağlık asistanınız MedSes. Lütfen belirtilerinizi söyleyin."
        addAssistant(text)
        speak(text, openMicAfter: true)
    }

    func stopAll() {
        silenceTask?.cancel()
        silenceTask = nil
        stopListening()
        synthesizer.stopSpeaking(at: .immediate)
        isAssistantSpeaking = false
        shouldOpenMicAfterSpeech = false
    }

    func handleUserText(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }

        addUser(cleaned)

        if isNoAnswer(cleaned) {
            finishSymptoms()
        } else {
            symptoms.append(cleaned)

            let question = "Belirtinizi kaydettim. Başka bir şikayetiniz var mı?"
            addAssistant(question)
            speak(question, openMicAfter: true)
        }
    }

    func toggleListening() {
        if isFinished { return }

        if isListening {
            finishCurrentSpeechIfPossible()
        } else {
            startListening()
        }
    }

    private func startListening() {
        guard !isAssistantSpeaking else { return }
        guard !synthesizer.isSpeaking else { return }

        stopListening()
        lastRecognizedText = ""

        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .duckOthers, .allowBluetooth]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            addAssistant("Mikrofon başlatılamadı.")
            print("AudioSession hatası:", error.localizedDescription)
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest else {
            addAssistant("Ses tanıma başlatılamadı.")
            return
        }

        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        let format = inputNode.inputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            addAssistant("Mikrofon formatı alınamadı. Gerçek cihazda deneyin.")
            print("Geçersiz format:", format)
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
            isListening = true
        } catch {
            addAssistant("Ses motoru çalıştırılamadı.")
            print("Audio engine hata:", error.localizedDescription)
            isListening = false
            return
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            Task { @MainActor in
                if let result {
                    let text = result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    if !text.isEmpty {
                        self.lastRecognizedText = text
                        print("Semptom algılandı:", text)
                        self.restartSilenceTimer()
                    }

                    if result.isFinal {
                        self.finishCurrentSpeechIfPossible()
                    }
                }

                if error != nil {
                    self.finishCurrentSpeechIfPossible()
                }
            }
        }

        restartSilenceTimer()
    }

    private func restartSilenceTimer() {
        silenceTask?.cancel()

        silenceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)

            await MainActor.run {
                self?.finishCurrentSpeechIfPossible()
            }
        }
    }

    private func finishCurrentSpeechIfPossible() {
        let text = lastRecognizedText.trimmingCharacters(in: .whitespacesAndNewlines)

        stopListening()

        guard !text.isEmpty else {
            let warning = "Sesinizi alamadım. Lütfen tekrar söyleyin."
            addAssistant(warning)
            speak(warning, openMicAfter: true)
            return
        }

        handleUserText(text)
    }
    private func stopListening() {
        silenceTask?.cancel()
        silenceTask = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        isListening = false
    }

    private func finishSymptoms() {
        stopListening()
        isFinished = true

        if symptoms.isEmpty {
            isFinished = false
            let text = "Hiç belirti eklemediniz. Lütfen en az bir belirti söyleyin."
            addAssistant(text)
            speak(text, openMicAfter: true)
            return
        }

        let text = "Belirtileriniz alındı. Şimdi uygun doktor ve klinik önerisini hazırlıyorum."
        addAssistant(text)
        speak(text, openMicAfter: false)

        Task {
            await analyzeSymptoms()
        }
    }

    private func analyzeSymptoms() async {
        aiStatus = "Analiz ediliyor..."

        do {
            var request = URLRequest(url: APIConfig.aiRecommendationURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let allSymptomsText = symptoms.joined(separator: ", ")
            let body = AiRequest(text: allSymptomsText)

            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse,
                  200..<300 ~= http.statusCode else {
                aiStatus = "Hata oluştu."
                addAssistant("Üzgünüm, şu an analiz yapamıyorum.")
                return
            }

            let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            let clinic = jsonObject?["tahmin_edilen_klinik"] as? String ?? ""
            let message = jsonObject?["sesli_okunacak_mesaj"] as? String
                ?? "Size \(clinic) polikliniğini öneriyorum."

            recommendedClinic = clinic

            addAssistant(message)
            speak(message, openMicAfter: false)

            aiStatus = "Analiz tamamlandı."

        } catch {
            aiStatus = "Bağlantı hatası."
            addAssistant("Bağlantı hatası oluştu: \(error.localizedDescription)")
            print("AI DECODE/REQUEST ERROR:", error)
        }
    }
    private func speak(_ text: String, openMicAfter: Bool) {
        stopListening()

        shouldOpenMicAfterSpeech = openMicAfter
        isAssistantSpeaking = true

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers]
            )
            try session.setActive(true)
        } catch {
            print("TTS AudioSession hata:", error.localizedDescription)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "tr-TR")
        utterance.rate = 0.45
        utterance.volume = 1.0

        print("Asistan konuşuyor:", text)
        synthesizer.speak(utterance)
    }
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            print("Asistan konuşması bitti.")

            self.isAssistantSpeaking = false

            guard self.shouldOpenMicAfterSpeech, !self.isFinished else {
                return
            }

            self.shouldOpenMicAfterSpeech = false

            try? await Task.sleep(nanoseconds: 1_200_000_000)

            print("Mikrofon tekrar açılıyor.")
            self.startListening()
        }
    }
    private func isNoAnswer(_ text: String) -> Bool {
        let lower = text.lowercased()

        return lower.contains("hayır") ||
               lower.contains("hayir") ||
               lower.contains("yok") ||
               lower.contains("başka yok") ||
               lower.contains("baska yok") ||
               lower.contains("tamam") ||
               lower.contains("bu kadar") ||
               lower.contains("yeterli")
    }

    private func addUser(_ text: String) {
        messages.append(SymptomChatMessage(text: text, isUser: true))
    }

    private func addAssistant(_ text: String) {
        messages.append(SymptomChatMessage(text: text, isUser: false))
    }

    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
    }
}

struct AiRequest: Codable {
    let text: String
}

struct AiResponse: Decodable {
    let tahminEdilenKlinik: String
    let sesliOkunacakMesaj: String

    enum CodingKeys: String, CodingKey {
        case tahminEdilenKlinik = "tahmin_edilen_klinik"
        case sesliOkunacakMesaj = "sesli_okunacak_mesaj"
    }
}

struct DoctorResponse: Codable, Identifiable {
    let id: Int?
    let name: String?
    let surname: String?
    let firstName: String?
    let lastName: String?
    let fullName: String?
    let clinicName: String?

    var safeId: Int {
        id ?? UUID().hashValue
    }
}
