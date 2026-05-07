import AVFoundation
import Speech
import Foundation

final class HomeVoiceManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    enum Step {
        case idle
        case askingVoicePermission
        case listeningVoicePermission
        case askingMainChoice
        case listeningMainChoice
        case askingAnotherRequest
        case listeningAnotherRequest
    }

    @Published var isListening = false

    var onReadAppointments: (() -> Void)?
    var onCreateAppointment: (() -> Void)?
    var onVoiceSymptom: (() -> Void)?
    var onManualMode: (() -> Void)?
    var onFamilyDoctorAppointment: (() -> Void)?
    var onProfile: (() -> Void)?
    var onLogout: (() -> Void)?

    private let mainMenuPrompt = "Hastane randevusu mu, aile hekimi randevusu mu, sesli semptom analizi mi, profil bilgilerinizi güncellemek mi istersiniz, yoksa randevularınızı mı okumak istersiniz?"

    private var step: Step = .idle
    private var didHandleCurrentSpeech = false

    private let synthesizer = AVSpeechSynthesizer()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    override init() {
        super.init()
        synthesizer.delegate = self

        SFSpeechRecognizer.requestAuthorization { status in
            print("Speech permission:", status.rawValue)
        }

        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            print("Mic permission:", granted)
        }
    }

    func startInitialFlow() {
        stopListening()

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        step = .askingVoicePermission
        speak("Sesli komutla devam etmek ister misiniz?")
    }

    func speakAndAskAnotherRequest(_ text: String) {
        step = .askingAnotherRequest
        speak(text)
    }

    func speakAndReturnToMenu(_ text: String) {
        step = .askingMainChoice
        speak(text)
    }

    func speak(_ text: String) {
        stopListening()

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
            print("TTS session hata:", error.localizedDescription)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "tr-TR")
        utterance.rate = 0.48
        utterance.volume = 1.0

        synthesizer.speak(utterance)
    }

    func stopAll() {
        synthesizer.stopSpeaking(at: .immediate)
        stopListening()
        step = .idle
        didHandleCurrentSpeech = false
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        switch step {
        case .askingVoicePermission:
            step = .listeningVoicePermission
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                self.startListening()
            }

        case .askingMainChoice:
            step = .listeningMainChoice
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                self.startListening()
            }

        case .askingAnotherRequest:
            step = .listeningAnotherRequest
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                self.startListening()
            }

        default:
            break
        }
    }

    private func startListening() {
        stopListening()
        didHandleCurrentSpeech = false

        guard recognizer?.isAvailable == true else {
            print("Speech recognizer uygun değil.")
            onManualMode?()
            return
        }

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.reset()
        }

        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .duckOthers, .allowBluetooth]
            )
            try session.setActive(true)
        } catch {
            print("Audio session hata:", error.localizedDescription)
            onManualMode?()
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest else {
            onManualMode?()
            return
        }

        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        let format = inputNode.inputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            print("Mikrofon formatı geçersiz:", format)
            onManualMode?()
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
            DispatchQueue.main.async {
                self.isListening = true
            }
        } catch {
            print("Audio engine hata:", error.localizedDescription)
            onManualMode?()
            return
        }

        recognitionTask = recognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString.lowercased()
                print("AnaSayfa algılanan:", text)

                if self.didHandleCurrentSpeech {
                    return
                }

                if self.containsCommand(text) {
                    self.didHandleCurrentSpeech = true

                    DispatchQueue.main.async {
                        self.handle(text)
                    }
                }
            }

            if error != nil {
                DispatchQueue.main.async {
                    self.stopListening()
                }
            }
        }
    }

    func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.reset()
        }

        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        DispatchQueue.main.async {
            self.isListening = false
        }
    }

    private func containsCommand(_ text: String) -> Bool {
        text.contains("evet") ||
        text.contains("hayır") ||
        text.contains("hayir") ||
        text.contains("hastane") ||
        text.contains("randevu oku") ||
        text.contains("randevuları oku") ||
        text.contains("randevularımı oku") ||
        text.contains("randevular") ||
        text.contains("oku") ||
        text.contains("oluştur") ||
        text.contains("olustur") ||
        text.contains("almak") ||
        text.contains("al") ||
        text.contains("semptom") ||
        text.contains("septum") ||
        text.contains("şikayet") ||
        text.contains("sikayet") ||
        text.contains("analiz") ||
        text.contains("aile") ||
        text.contains("hekim") ||
        text.contains("profil") ||
        text.contains("güncelle") ||
        text.contains("guncelle") ||
        text.contains("çıkış") ||
        text.contains("cikis") ||
        text.contains("kapat") ||
        text.contains("manuel")
    }


    private func handle(_ text: String) {
        switch step {

        case .listeningVoicePermission:
            if text.contains("evet") {
                stopListening()
                step = .askingMainChoice
                speak(mainMenuPrompt)

            } else if text.contains("hayır") || text.contains("hayir") {
                stopListening()
                step = .idle
                speak("Tamam, manuel olarak devam edebilirsiniz.")
                onManualMode?()
            }
        case .listeningMainChoice:
            if text.contains("çıkış") || text.contains("cikis") || text.contains("kapat") {
                stopListening()
                step = .idle
                onLogout?()

            } else if text.contains("oku") ||
                        text.contains("randevular") ||
                        text.contains("randevularımı") ||
                        text.contains("randevu oku") {
                stopListening()
                step = .idle
                onReadAppointments?()

            } else if text.contains("aile") || text.contains("hekim") {
                stopListening()
                step = .idle
                onFamilyDoctorAppointment?()

            } else if text.contains("profil") || text.contains("güncelle") || text.contains("guncelle") {
                stopListening()
                step = .idle
                onProfile?()

            } else if text.contains("semptom") ||
                        text.contains("septum") ||
                        text.contains("şikayet") ||
                        text.contains("sikayet") ||
                        text.contains("analiz") {
                stopListening()
                step = .idle
                onVoiceSymptom?()

            } else if text.contains("hastane") ||
                        text.contains("randevu al") ||
                        text.contains("randevu almak") ||
                        text.contains("oluştur") ||
                        text.contains("olustur") {
                stopListening()
                step = .idle
                onCreateAppointment?()

            } else if text.contains("hayır") ||
                        text.contains("hayir") ||
                        text.contains("manuel") {
                stopListening()
                step = .idle
                speak("Tamam, manuel olarak devam edebilirsiniz.")
                onManualMode?()

            } else {
                stopListening()
                step = .askingMainChoice
                speak("Anlayamadım. \(mainMenuPrompt)")
            }
        case .listeningAnotherRequest:
            if text.contains("evet") {
                stopListening()
                step = .askingMainChoice
                speak(mainMenuPrompt)

            } else if text.contains("çıkış") || text.contains("cikis") || text.contains("kapat") {
                stopListening()
                step = .idle
                onLogout?()

            } else if text.contains("hayır") || text.contains("hayir") || text.contains("manuel") {
                stopListening()
                step = .idle
                speak("Tamam, manuel olarak devam edebilirsiniz.")
                onManualMode?()

            } else {
                stopListening()
                step = .askingAnotherRequest
                speak("Anlayamadım. Başka isteğiniz var mı?")
            }


        default:
            break
        }
    }
}
