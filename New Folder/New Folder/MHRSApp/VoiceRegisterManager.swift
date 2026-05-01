import Foundation
import Speech
import AVFoundation

final class VoiceRegisterManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    enum Step {
        case idle
        case name
        case surname
        case tc
        case birthDate
        case gender
        case pin
        case voiceSamples
        case finished
    }

    @Published var stepText = ""
    @Published var isListening = false
    @Published var isRecording = false
    @Published var sampleCount = 0
    @Published var statusMessage = ""

    @Published var name = ""
    @Published var surname = ""
    @Published var tcKimlik = ""
    @Published var dogumTarihi = ""
    @Published var cinsiyet = ""
    @Published var password = ""

    var onFinished: (() -> Void)?
    var onError: ((String) -> Void)?

    private var step: Step = .idle

    private let synthesizer = AVSpeechSynthesizer()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private var audioRecorder: AVAudioRecorder?
    private var sampleURLs: [URL] = []

    private var shouldListenAfterSpeak = false
    private var shouldRecordAfterSpeak = false
    private var isSpeakingNow = false

    private var speechDebounceTimer: Timer?
    private var lastRecognizedText = ""

    override init() {
        super.init()
        synthesizer.delegate = self

        SFSpeechRecognizer.requestAuthorization { _ in }
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            print("Mikrofon izni:", granted)
        }
    }

    func startVoiceRegister() {
        resetAll()
        step = .name
        askCurrentStep()
    }

    private func resetAll() {
        stopListening()
        audioRecorder?.stop()

        sampleURLs.removeAll()
        sampleCount = 0

        name = ""
        surname = ""
        tcKimlik = ""
        dogumTarihi = ""
        cinsiyet = ""
        password = ""

        stepText = ""
        statusMessage = ""
        isRecording = false
        isListening = false
        isSpeakingNow = false

        speechDebounceTimer?.invalidate()
        speechDebounceTimer = nil
        lastRecognizedText = ""
    }

    private func askCurrentStep() {
        switch step {
        case .name:
            speakThenListen("Sesli kayıt başlıyor. Lütfen adınızı söyleyin.")

        case .surname:
            speakThenListen("Lütfen soyadınızı söyleyin.")

        case .tc:
            speakThenListen("Lütfen 11 haneli TC kimlik numaranızı rakam rakam söyleyin.")

        case .birthDate:
            speakThenListen("Lütfen doğum tarihinizi gün ay yıl olarak söyleyin. Örneğin dört şubat iki bin iki.")

        case .gender:
            speakThenListen("Lütfen cinsiyetinizi kadın ya da erkek olarak söyleyin.")

        case .pin:
            speakThenListen("Lütfen 4 haneli PIN şifrenizi rakam rakam söyleyin.")

        case .voiceSamples:
            startVoiceSampleFlow()

        default:
            break
        }
    }

    private func speakThenListen(_ text: String) {
        stepText = text
        shouldListenAfterSpeak = true
        shouldRecordAfterSpeak = false
        speak(text)
    }

    private func speakThenRecord(_ text: String) {
        stepText = text
        shouldRecordAfterSpeak = true
        shouldListenAfterSpeak = false
        speak(text)
    }

    private func speak(_ text: String) {
        stopListening()
        isSpeakingNow = true

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
        try? session.setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "tr-TR")
        utterance.rate = 0.45

        synthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeakingNow = false

        if shouldListenAfterSpeak {
            shouldListenAfterSpeak = false

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self.startListening()
            }
        }

        if shouldRecordAfterSpeak {
            shouldRecordAfterSpeak = false

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self.startVoiceSampleRecording()
            }
        }
    }

    private func startListening() {
        stopListening()

        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true)
        } catch {
            onError?("Ses oturumu başlatılamadı: \(error.localizedDescription)")
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else {
            onError?("Ses tanıma isteği oluşturulamadı.")
            return
        }

        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.inputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            onError?("Mikrofon formatı geçersiz.")
            return
        }

        inputNode.removeTap(onBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
            isListening = true
            stepText = stepText + "\n\nDinleniyor..."
        } catch {
            onError?("Mikrofon başlatılamadı: \(error.localizedDescription)")
            return
        }

        recognitionTask = recognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if self.isSpeakingNow {
                return
            }

            if let result {
                let text = result.bestTranscription.formattedString
                    .lowercased()
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                guard !text.isEmpty else { return }

                print("Sesli kayıt algılanan:", text)

                self.lastRecognizedText = text
                self.speechDebounceTimer?.invalidate()

                let waitTime: TimeInterval

                switch self.step {
                case .name:
                    waitTime = 2.2
                case .surname:
                    waitTime = 2.2
                case .tc:
                    waitTime = 4.5
                case .birthDate:
                    waitTime = 4.0
                case .gender:
                    waitTime = 2.5
                case .pin:
                    waitTime = 3.0
                default:
                    waitTime = 2.0
                }

                self.speechDebounceTimer = Timer.scheduledTimer(withTimeInterval: waitTime, repeats: false) { _ in
                    self.handleRecognizedText(self.lastRecognizedText)
                }
            }

            if error != nil {
                self.stopListening()
            }
        }
    }

    private func stopListening() {
        speechDebounceTimer?.invalidate()
        speechDebounceTimer = nil
        lastRecognizedText = ""

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

    private func handleRecognizedText(_ text: String) {
        let cleanText = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanText.isEmpty else {
            repeatCurrentStep("Sizi anlayamadım. Lütfen tekrar söyleyin.")
            return
        }

        stopListening()

        switch step {
        case .name:
            let value = capitalizeWords(cleanText)

            guard value.count >= 2 else {
                repeatCurrentStep("Adınız anlaşılamadı. Lütfen adınızı tekrar söyleyin.")
                return
            }

            name = value
            step = .surname

        case .surname:
            let value = capitalizeWords(cleanText)

            guard value.count >= 2 else {
                repeatCurrentStep("Soyadınız anlaşılamadı. Lütfen soyadınızı tekrar söyleyin.")
                return
            }

            surname = value
            step = .tc

        case .tc:
            let digits = normalizeSpokenNumbers(cleanText)

            guard digits.count == 11 else {
                repeatCurrentStep("TC kimlik numarası 11 haneli olmalıdır. Algılanan \(digits.count) hane. Lütfen tekrar söyleyin.")
                return
            }

            tcKimlik = digits
            step = .birthDate

        case .birthDate:
            let formatted = formatSpokenDate(cleanText)

            guard !formatted.isEmpty else {
                repeatCurrentStep("Doğum tarihiniz anlaşılamadı. Lütfen gün ay yıl şeklinde tekrar söyleyin.")
                return
            }

            dogumTarihi = formatted
            step = .gender

        case .gender:
            let gender = normalizeGender(cleanText)

            guard !gender.isEmpty else {
                repeatCurrentStep("Cinsiyet anlaşılamadı. Lütfen kadın ya da erkek olarak söyleyin.")
                return
            }

            cinsiyet = gender
            step = .pin

        case .pin:
            let digits = normalizeSpokenNumbers(cleanText)

            guard digits.count == 4 else {
                repeatCurrentStep("PIN 4 haneli olmalıdır. Algılanan \(digits.count) hane. Lütfen tekrar söyleyin.")
                return
            }

            password = digits
            step = .voiceSamples

        default:
            break
        }

        askCurrentStep()
    }

    private func repeatCurrentStep(_ message: String) {
        speakThenListen(message)
    }

    private func startVoiceSampleFlow() {
        sampleCount = 0
        sampleURLs.removeAll()

        speakThenRecord("Bilgiler alındı. Şimdi ses profiliniz için 3 kez ses kaydı alınacak. Her kayıtta ekrandaki süre boyunca net şekilde konuşun. İlk kayıt başlıyor.")
    }

    private func startVoiceSampleRecording() {
        guard sampleCount < 3 else {
            Task {
                await uploadVoiceRegister()
            }
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("register_sample_\(sampleCount).wav")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()

            isRecording = true
            stepText = "\(sampleCount + 1). ses kaydı alınıyor. Lütfen 5 saniye boyunca net konuşun."

            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                self.audioRecorder?.stop()
                self.audioRecorder = nil
                self.isRecording = false

                self.sampleURLs.append(url)
                self.sampleCount += 1

                if self.sampleCount < 3 {
                    self.speakThenRecord("\(self.sampleCount). kayıt alındı. Sıradaki kayıt başlıyor.")
                } else {
                    self.stepText = "Ses kayıtları tamamlandı. Sunucuya gönderiliyor."
                    Task {
                        await self.uploadVoiceRegister()
                    }
                }
            }

        } catch {
            onError?("Ses kaydı başlatılamadı: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func uploadVoiceRegister() async {
        guard !name.isEmpty,
              !surname.isEmpty,
              tcKimlik.count == 11,
              !dogumTarihi.isEmpty,
              !cinsiyet.isEmpty,
              password.count == 4 else {
            onError?("Tüm bilgiler alınmadan kullanıcı oluşturulamaz.")
            return
        }

        guard sampleURLs.count == 3 else {
            onError?("3 adet ses kaydı alınamadı.")
            return
        }

        do {
            var request = URLRequest(url: APIConfig.registerVoiceURL)
            request.httpMethod = "POST"

            let boundary = UUID().uuidString
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            var body = Data()

            for fileURL in sampleURLs {
                let audioData = try Data(contentsOf: fileURL)

                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"files\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
                body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
                body.append(audioData)
                body.append("\r\n".data(using: .utf8)!)
            }

            let fields: [String: String] = [
                "name": name,
                "surname": surname,
                "tcKimlik": tcKimlik,
                "password": password,
                "cinsiyet": cinsiyet,
                "dogumTarihi": dogumTarihi
            ]

            for (key, value) in fields {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(value)\r\n".data(using: .utf8)!)
            }

            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            request.httpBody = body

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                onError?("Sunucu cevabı alınamadı.")
                return
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                let msg = String(data: data, encoding: .utf8) ?? "Sesli kayıt başarısız."
                onError?(msg)
                return
            }

            statusMessage = "Sesli kayıt başarılı."
            stepText = "Kaydınız başarıyla oluşturuldu."
            step = .finished
            onFinished?()

        } catch {
            onError?("Sesli kayıt bağlantı hatası: \(error.localizedDescription)")
        }
    }

    private func normalizeSpokenNumbers(_ spoken: String) -> String {
        let map: [String: String] = [
            "sıfır": "0", "sifir": "0",
            "bir": "1",
            "iki": "2",
            "üç": "3", "uc": "3", "üc": "3",
            "dört": "4", "dort": "4",
            "beş": "5", "bes": "5",
            "altı": "6", "alti": "6",
            "yedi": "7",
            "sekiz": "8",
            "dokuz": "9"
        ]

        let clean = spoken.lowercased()
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        var result = ""

        for token in clean.split(separator: " ") {
            let word = String(token)

            if word.allSatisfy(\.isNumber) {
                result += word
            } else if let digit = map[word] {
                result += digit
            }
        }

        return result
    }

    private func formatSpokenDate(_ spoken: String) -> String {
        let lower = spoken.lowercased()

        let monthMap: [String: String] = [
            "ocak": "01",
            "şubat": "02", "subat": "02",
            "mart": "03",
            "nisan": "04",
            "mayıs": "05", "mayis": "05",
            "haziran": "06",
            "temmuz": "07",
            "ağustos": "08", "agustos": "08",
            "eylül": "09", "eylul": "09",
            "ekim": "10",
            "kasım": "11", "kasim": "11",
            "aralık": "12", "aralik": "12"
        ]

        for (monthName, monthNumber) in monthMap {
            if lower.contains(monthName) {
                let digits = normalizeSpokenNumbers(lower)
                let day = String(digits.prefix(2)).leftPadding(toLength: 2, withPad: "0")

                let year = extractYear(from: lower)

                if !day.isEmpty, !year.isEmpty {
                    return "\(year)-\(monthNumber)-\(day)"
                }
            }
        }

        let digits = normalizeSpokenNumbers(lower)

        if digits.count >= 8 {
            let day = String(digits.prefix(2))
            let monthStart = digits.index(digits.startIndex, offsetBy: 2)
            let monthEnd = digits.index(digits.startIndex, offsetBy: 4)
            let month = String(digits[monthStart..<monthEnd])
            let year = String(digits.suffix(4))

            return "\(year)-\(month)-\(day)"
        }

        return ""
    }

    private func extractYear(from text: String) -> String {
        let numbers = text.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()

        if numbers.count >= 4 {
            return String(numbers.suffix(4))
        }

        if text.contains("iki bin iki") {
            return "2002"
        }

        if text.contains("iki bin bir") {
            return "2001"
        }

        if text.contains("iki bin") {
            return "2000"
        }

        return ""
    }

    private func normalizeGender(_ spoken: String) -> String {
        let lower = spoken.lowercased()

        if lower.contains("kadın") || lower.contains("kadin") {
            return "Kadın"
        }

        if lower.contains("erkek") {
            return "Erkek"
        }

        return ""
    }

    private func capitalizeWords(_ text: String) -> String {
        text.lowercased()
            .split(separator: " ")
            .map { word in
                word.prefix(1).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }
}

private extension String {
    func leftPadding(toLength: Int, withPad character: Character) -> String {
        let paddingCount = toLength - self.count

        guard paddingCount > 0 else {
            return self
        }

        return String(repeating: String(character), count: paddingCount) + self
    }
}
