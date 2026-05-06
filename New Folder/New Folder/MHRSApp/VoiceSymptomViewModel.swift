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
    @Published var shouldNavigateToAppointment = false

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private let synthesizer = AVSpeechSynthesizer()

    private var shouldOpenMicAfterSpeech = false
    private var shouldNavigateAfterSpeech = false
    private var isFinished = false
    private var isProcessingSpeech = false

    private var lastRecognizedText = ""
    private var lastProcessedText = ""
    private var silenceTask: Task<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func start() {
        requestPermissions()

        guard messages.isEmpty else { return }

        let text = "Merhaba, ben sesli asistanınız MedSes. Lütfen belirtilerinizi söyleyin."
        addAssistant(text)
        speak(text, openMicAfter: true)
    }

    func stopAll() {
        silenceTask?.cancel()
        silenceTask = nil

        stopListening()

        synthesizer.stopSpeaking(at: .immediate)

        isListening = false
        isAssistantSpeaking = false
        shouldOpenMicAfterSpeech = false
        shouldNavigateAfterSpeech = false
        isProcessingSpeech = false
    }

    func toggleListening() {
        guard !isFinished else { return }

        if isListening {
            finishCurrentSpeechIfPossible()
        } else {
            startListening()
        }
    }

    func handleUserText(_ text: String) {
        let cleaned = cleanText(text)

        guard !cleaned.isEmpty else { return }

        if cleaned == lastProcessedText {
            return
        }

        lastProcessedText = cleaned
        addUser(cleaned)

        if isNoAnswer(cleaned) {
            finishSymptoms()
            return
        }

        symptoms.append(cleaned)

        let question = "Belirtinizi kaydettim. Başka bir şikayetiniz var mı?"
        addAssistant(question)
        speak(question, openMicAfter: true)
    }

    private func startListening() {
        guard !isAssistantSpeaking else { return }
        guard !synthesizer.isSpeaking else { return }
        guard !isProcessingSpeech else { return }
        guard !isFinished else { return }

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
        recognitionRequest.requiresOnDeviceRecognition = false
        
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        let format = inputNode.inputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            addAssistant("Mikrofon formatı alınamadı. Gerçek cihazda deneyin.")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
            isListening = true
            restartSilenceTimer()
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
                        self.restartSilenceTimer()
                    }
                }
                if let error {
                    print("Speech geçici hata:", error.localizedDescription)
                }
            }
        }
    }
    private func restartSilenceTimer() {
        silenceTask?.cancel()

        silenceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)

            await MainActor.run {
                self?.finishCurrentSpeechIfPossible()
            }
        }
    }
    private func finishCurrentSpeechIfPossible() {
        guard !isProcessingSpeech else { return }

        let text = cleanText(lastRecognizedText)

        isProcessingSpeech = true

        stopListening()

        guard !text.isEmpty else {
            isProcessingSpeech = false

            let warning = "Sesinizi alamadım. Lütfen tekrar söyleyin."
            addAssistant(warning)
            speak(warning, openMicAfter: true)
            return
        }

        handleUserText(text)

        isProcessingSpeech = false
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

        if symptoms.isEmpty {
            let text = "Henüz belirti eklemediniz. Lütfen en az bir belirti söyleyin."
            addAssistant(text)
            speak(text, openMicAfter: true)
            return
        }

        isFinished = true

        let text = "Belirtilerinizi aldım. Şimdi size uygun polikliniği hazırlıyorum."
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

            let decoded = try JSONDecoder().decode(AiResponse.self, from: data)

            recommendedClinic = decoded.tahminEdilenKlinik
            aiStatus = "Analiz tamamlandı."

            let message = decoded.sesliOkunacakMesaj
            addAssistant(message)

            shouldNavigateAfterSpeech = true
            speak(message, openMicAfter: false)

        } catch {
            aiStatus = "Bağlantı hatası."
            addAssistant("Bağlantı hatası oluştu.")
            print("AI ERROR:", error.localizedDescription)
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

        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isAssistantSpeaking = false

            if self.shouldNavigateAfterSpeech {
                self.shouldNavigateAfterSpeech = false
                self.shouldNavigateToAppointment = true
                return
            }

            guard self.shouldOpenMicAfterSpeech, !self.isFinished else {
                return
            }

            self.shouldOpenMicAfterSpeech = false

            try? await Task.sleep(nanoseconds: 700_000_000)

            self.startListening()
        }
    }

    private func isNoAnswer(_ text: String) -> Bool {
        let lower = text.lowercased()

        return lower == "hayır" ||
               lower == "hayir" ||
               lower == "yok" ||
               lower.contains("başka yok") ||
               lower.contains("baska yok") ||
               lower.contains("bu kadar") ||
               lower.contains("yeter") ||
               lower.contains("yeterli") ||
               lower.contains("devam etme")
    }

    private func cleanText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
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

// MARK: - API DTO

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
