import Foundation
import Speech
import AVFoundation

enum VoiceState {
    case idle
    case askingPermission
    case listeningForPermission
    case askingTC
}

class VoiceManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    @Published var isListening = false

    var onVoiceTCRecorded: ((URL) -> Void)?
    var onVoiceLoginRecorded: ((URL) -> Void)?
    var onManualLoginSelected: (() -> Void)?
    var onSpeakFinished: (() -> Void)?

    private var currentState: VoiceState = .idle

    private let speechSynthesizer = AVSpeechSynthesizer()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var audioRecorder: AVAudioRecorder?
    private var recordedAudioURL: URL?
    private var recordTimer: Timer?

    override init() {
        super.init()
        speechSynthesizer.delegate = self
        requestPermissions()
    }

    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            print("Mic izin:", granted)
        }
    }

    func startInitialFlow() {
        currentState = .askingPermission
        speak("Sesli komutla devam etmek ister misiniz?")
    }

    func speak(_ text: String) {
        stopListening()

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
        try? audioSession.setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "tr-TR")
        speechSynthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        switch currentState {

        case .askingPermission:
            currentState = .listeningForPermission
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.startListening()
            }

        case .askingTC:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.startRecordingTCVoice()
            }

        default:
            onSpeakFinished?()
        }
    }

    func startListening() {
        stopListening()

        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
            try audioSession.setActive(true)
        } catch {
            print("AudioSession hatası:", error.localizedDescription)
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }

        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.inputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            print("Mikrofon formatı geçersiz.")
            return
        }

        inputNode.removeTap(onBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
            isListening = true
        } catch {
            print("AudioEngine başlatılamadı:", error.localizedDescription)
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result = result {
                let text = result.bestTranscription.formattedString.lowercased()
                print("🎤 ALGILANAN:", text)
                self.handleRecognizedText(text)
            }

            if error != nil {
                self.stopListening()
            }
        }
    }

    func stopListening() {
        recordTimer?.invalidate()
        recordTimer = nil

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

    func startRecordingTCVoice() {
        stopListening()

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tc.wav")
        recordedAudioURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            isListening = true

            recordTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { _ in
                self.stopRecordingTCVoice()
            }
        } catch {
            print("TC ses kaydı başlatılamadı:", error.localizedDescription)
        }
    }

    func stopRecordingTCVoice() {
        recordTimer?.invalidate()
        recordTimer = nil

        audioRecorder?.stop()
        isListening = false

        if let url = recordedAudioURL {
            onVoiceTCRecorded?(url)
        }
    }

    func startRecordingVoiceForLogin() {
        stopListening()

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("login.wav")
        recordedAudioURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            isListening = true

            recordTimer = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { _ in
                self.stopRecordingVoiceForLogin()
            }
        } catch {
            print("Login ses kaydı başlatılamadı:", error.localizedDescription)
        }
    }

    func stopRecordingVoiceForLogin() {
        recordTimer?.invalidate()
        recordTimer = nil

        audioRecorder?.stop()
        isListening = false

        if let url = recordedAudioURL {
            onVoiceLoginRecorded?(url)
        }
    }

    private func handleRecognizedText(_ text: String) {
        switch currentState {

        case .listeningForPermission:
            if text.contains("evet") {
                stopListening()
                currentState = .askingTC
                speak("TC kimlik numaranızı söyleyin")
            } else if text.contains("hayır") || text.contains("hayir") {
                stopListening()
                currentState = .idle
                speak("Manuel giriş yapabilirsiniz")
                onManualLoginSelected?()
            }

        default:
            break
        }
    }
}
