import Foundation
import Speech
import AVFoundation

@MainActor
final class VoiceSymptomViewModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    enum VoiceStep {
        case idle
        case listeningSymptom
        case listeningAnotherAnswer
        case choosingClinic
        case finished
    }

    @Published var messages: [SymptomChatMessage] = []
    @Published var symptoms: [String] = []
    @Published var clinicOptions: [String] = []
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
    private var activeUtterance: AVSpeechUtterance?

    private var currentStep: VoiceStep = .idle
    private var shouldOpenMicAfterSpeech = false
    private var shouldNavigateAfterSpeech = false
    private var isFinished = false
    private var isProcessingSpeech = false

    private var lastRecognitionUpdateDate = Date()
    private let symptomSilenceSeconds: TimeInterval = 4.0
    private let answerSilenceSeconds: TimeInterval = 3.0
    private let clinicChoiceSilenceSeconds: TimeInterval = 3.0

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

        currentStep = .listeningSymptom

        let text = "Merhaba, ben sesli asistanınız MedSes. Belirtinizi söyleyin."
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
        currentStep = .idle
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

        switch currentStep {
        case .listeningSymptom:
            saveSymptom(cleaned)

        case .listeningAnotherAnswer:
            if isNoAnswer(cleaned) {
                finishSymptoms()
            } else {
                saveSymptom(cleaned)
            }

        case .choosingClinic:
            handleClinicChoice(cleaned)

        default:
            break
        }
    }

    private func saveSymptom(_ symptom: String) {
        let cleaned = cleanText(symptom)

        guard cleaned.count >= 3 else {
            let warning = "Belirtinizi tam alamadım. Lütfen tekrar söyleyin."
            addAssistant(warning)
            speak(warning, openMicAfter: true)
            return
        }

        let alreadyExists = symptoms.contains {
            normalizeTurkish($0) == normalizeTurkish(cleaned)
        }

        if !alreadyExists {
            symptoms.append(cleaned)
        }

        currentStep = .listeningAnotherAnswer

        let question = "Başka belirtiniz varsa söyleyin, yoksa yok deyin."
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
        lastProcessedText = ""
        lastRecognitionUpdateDate = Date()

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
        recognitionRequest.taskHint = .dictation

        recognitionRequest.contextualStrings = [
            "başım ağrıyor",
            "baş ağrısı",
            "midem bulanıyor",
            "kusma",
            "ateşim var",
            "öksürüyorum",
            "boğazım ağrıyor",
            "nefes almakta zorlanıyorum",
            "göğsüm ağrıyor",
            "halsizlik",
            "halsizim",
            "baş dönmesi",
            "karın ağrısı",
            "yok",
            "başka yok",
            "bu kadar",
            "birinci",
            "ikinci",
            "üçüncü",
            "göğüs hastalıkları",
            "enfeksiyon hastalıkları",
            "iç hastalıkları",
            "dahiliye",
            "kulak burun boğaz",
            "kardiyoloji",
            "nöroloji",
            "acil tıp",
            "aile hekimliği"
        ]

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
                        if text.count >= self.lastRecognizedText.count {
                            self.lastRecognizedText = text
                        }

                        self.lastRecognitionUpdateDate = Date()
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

        let waitSeconds: TimeInterval

        switch currentStep {
        case .listeningSymptom:
            waitSeconds = symptomSilenceSeconds
        case .listeningAnotherAnswer:
            waitSeconds = answerSilenceSeconds
        case .choosingClinic:
            waitSeconds = clinicChoiceSilenceSeconds
        default:
            waitSeconds = 2.5
        }

        silenceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(waitSeconds * 1_000_000_000))

            await MainActor.run {
                guard let self else { return }

                let elapsed = Date().timeIntervalSince(self.lastRecognitionUpdateDate)

                if elapsed >= waitSeconds - 0.2 {
                    self.finishCurrentSpeechIfPossible()
                } else {
                    self.restartSilenceTimer()
                }
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

            let warning: String

            switch currentStep {
            case .listeningAnotherAnswer:
                warning = "Başka belirtiniz varsa söyleyin, yoksa yok deyin."
            case .choosingClinic:
                warning = "Lütfen birinci, ikinci, üçüncü diyerek ya da bölüm adını söyleyerek seçim yapın."
            default:
                warning = "Sesinizi alamadım. Lütfen tekrar söyleyin."
            }

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
            audioEngine.reset()
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
            currentStep = .listeningSymptom

            let text = "Henüz belirti eklemediniz. Lütfen en az bir belirti söyleyin."
            addAssistant(text)
            speak(text, openMicAfter: true)
            return
        }

        currentStep = .finished
        isFinished = false

        let text = "Belirtilerinizi topladım. İlgili poliklinikler bulunuyor."
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

            print("AI URL:", APIConfig.aiRecommendationURL.absoluteString)
            print("Gönderilen belirtiler:", allSymptomsText)

            let body = AiRequest(text: allSymptomsText)
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                aiStatus = "Sunucu yanıtı alınamadı."
                addAssistant("Sunucu yanıtı alınamadı.")
                return
            }

            let responseText = String(data: data, encoding: .utf8) ?? ""
            print("HTTP STATUS:", http.statusCode)
            print("AI RESPONSE:", responseText)

            guard 200..<300 ~= http.statusCode else {
                aiStatus = "Hata oluştu."
                addAssistant("Üzgünüm, şu an analiz yapamıyorum.")
                return
            }

            let decoded = try JSONDecoder().decode(AiResponse.self, from: data)

            aiStatus = "Analiz tamamlandı."

            var options = Array(decoded.klinikAdaylari.prefix(3))

            if options.isEmpty, !decoded.tahminEdilenKlinik.isEmpty {
                options = [decoded.tahminEdilenKlinik]
            }

            guard !options.isEmpty else {
                currentStep = .listeningSymptom
                isFinished = false

                let message = "Uygun poliklinik bulunamadı. Lütfen belirtilerinizi tekrar söyleyin."
                addAssistant(message)
                speak(message, openMicAfter: true)
                return
            }

            clinicOptions = options
            recommendedClinic = ""
            currentStep = .choosingClinic
            isFinished = false
            shouldNavigateAfterSpeech = false

            let optionText = clinicOptions.enumerated().map { index, clinic in
                "\(index + 1). \(clinic)"
            }.joined(separator: ", ")

            let message = "Belirtilerinize göre önerilen bölümler şunlar: \(optionText). Hangi bölümü seçmek istersiniz? Birinci, ikinci, üçüncü diyebilir ya da bölüm adını söyleyebilirsiniz."

            addAssistant(message)

            // Klinikler okunduktan sonra mikrofon açılır.
            speak(message, openMicAfter: true)

        } catch {
            aiStatus = "Bağlantı hatası."
            addAssistant("Bağlantı hatası oluştu.")
            print("AI ERROR:", error.localizedDescription)
        }
    }
    private func handleClinicChoice(_ text: String) {
        let normalized = normalizeTurkish(text)

        var selected: String?

        if normalized.contains("birinci") || normalized == "bir" || normalized.contains("1") || normalized.contains("ilk") {
            selected = clinicOptions.indices.contains(0) ? clinicOptions[0] : nil
        } else if normalized.contains("ikinci") || normalized == "iki" || normalized.contains("2") {
            selected = clinicOptions.indices.contains(1) ? clinicOptions[1] : nil
        } else if normalized.contains("ucuncu") || normalized == "uc" || normalized.contains("3") {
            selected = clinicOptions.indices.contains(2) ? clinicOptions[2] : nil
        } else {
            selected = clinicOptions.first { clinic in
                let normalizedClinic = normalizeTurkish(clinic)
                return normalizedClinic.contains(normalized) || normalized.contains(normalizedClinic)
            }
        }

        guard let selected else {
            let message = "Seçiminizi anlayamadım. Birinci, ikinci, üçüncü diyebilir ya da bölüm adını söyleyebilirsiniz."
            addAssistant(message)
            speak(message, openMicAfter: true)
            return
        }

        recommendedClinic = selected
        clinicOptions = []
        currentStep = .finished
        isFinished = true

        let message = "\(selected) seçildi. Hastane randevu ekranına yönlendiriliyorsunuz."
        addAssistant(message)

        // Klinik seçilmeden yönlendirme yapılmaz. Seçimden sonra konuşma bitince yönlendirir.
        shouldNavigateAfterSpeech = true
        speak(message, openMicAfter: false)
    }
    private func speak(_ text: String, openMicAfter: Bool) {
        stopListening()

        if synthesizer.isSpeaking {
            activeUtterance = nil
            synthesizer.stopSpeaking(at: .immediate)
        }

        shouldOpenMicAfterSpeech = openMicAfter
        isAssistantSpeaking = true

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

        activeUtterance = utterance
        synthesizer.speak(utterance)
    }
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            guard self.activeUtterance === utterance else { return }

            self.activeUtterance = nil
            self.handleAssistantSpeechFinished()
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            guard self.activeUtterance === utterance else { return }

            self.activeUtterance = nil
            self.isAssistantSpeaking = false
        }
    }

    private func handleAssistantSpeechFinished() {
        isAssistantSpeaking = false

        if shouldNavigateAfterSpeech {
            shouldNavigateAfterSpeech = false
            shouldNavigateToAppointment = true
            return
        }

        guard shouldOpenMicAfterSpeech, !isFinished else {
            return
        }

        shouldOpenMicAfterSpeech = false

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            startListening()
        }
    }

    private func isNoAnswer(_ text: String) -> Bool {
        let lower = normalizeTurkish(text)

        return lower == "hayir" ||
               lower == "yok" ||
               lower == "yok yok" ||
               lower.contains("baska yok") ||
               lower.contains("belirtim yok") ||
               lower.contains("sikayetim yok") ||
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

    private func normalizeTurkish(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "ğ", with: "g")
            .replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: "ş", with: "s")
            .replacingOccurrences(of: "ö", with: "o")
            .replacingOccurrences(of: "ç", with: "c")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
    let klinikAdaylari: [String]
    let sesliOkunacakMesaj: String
    let hastalikTahmin: String
    let guvenOrani: Double
    let aciliyetDurumu: String
    let acilUyarisi: String

    enum CodingKeys: String, CodingKey {
        case tahminEdilenKlinik = "tahmin_edilen_klinik"
        case klinikAdaylari = "klinik_adaylari"
        case sesliOkunacakMesaj = "sesli_okunacak_mesaj"
        case onerilenKlinik = "onerilen_klinik"
        case hastalikTahmin = "hastalik_tahmin"
        case guvenOrani = "guven_orani"
        case aciliyetDurumu = "aciliyet_durumu"
        case acilUyarisi = "acil_uyarisi"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let liste1 = try? container.decodeIfPresent([String].self, forKey: .tahminEdilenKlinik)
        let liste2 = try? container.decodeIfPresent([String].self, forKey: .onerilenKlinik)
        let liste3 = try? container.decodeIfPresent([String].self, forKey: .klinikAdaylari)

        let backendKlinikler = liste1 ?? liste2 ?? liste3 ?? []

        self.tahminEdilenKlinik = backendKlinikler.first ?? ""
        self.klinikAdaylari = backendKlinikler

        self.hastalikTahmin = (try? container.decodeIfPresent(String.self, forKey: .hastalikTahmin)) ?? ""
        self.guvenOrani = (try? container.decodeIfPresent(Double.self, forKey: .guvenOrani)) ?? 0.0
        self.aciliyetDurumu = (try? container.decodeIfPresent(String.self, forKey: .aciliyetDurumu)) ?? "NORMAL"
        self.acilUyarisi = (try? container.decodeIfPresent(String.self, forKey: .acilUyarisi)) ?? ""

        self.sesliOkunacakMesaj =
            (try? container.decodeIfPresent(String.self, forKey: .sesliOkunacakMesaj)) ??
            "Belirtilerinize göre önerilen bölümler: \(backendKlinikler.prefix(3).joined(separator: ", "))"
    }
}
