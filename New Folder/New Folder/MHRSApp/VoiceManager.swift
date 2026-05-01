import Foundation
import Speech
import AVFoundation

enum VoiceState {
    case idle, askingPermission, listeningForPermission, askingTC, listeningForTC, askingPassword, listeningForPassword, assistantFlow, finished
}

class VoiceManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isListening = false
    @Published var recognizedText = ""
    @Published var isVoiceModeActive = false
    
    var onTCDidChange: ((String) -> Void)?
    var onPasswordDidChange: ((String) -> Void)?
    var onLoginTrigger: (() -> Void)?
    
    // Ana Sayfa için yeni geri çağrımlar
    var onSpeechFinished: (() -> Void)?
    var onCommandRecognized: ((String) -> Void)?
    
    private var currentState: VoiceState = .idle
    private let speechSynthesizer = AVSpeechSynthesizer()
    private let assistantSynthesizer = AVSpeechSynthesizer() // Ana sayfa için ayrı
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var silenceTimer: Timer?
    private var assistantCompletion: (() -> Void)?

    override init() {
        super.init()
        speechSynthesizer.delegate = self
        assistantSynthesizer.delegate = self
        requestPermissions()
    }
    
    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { _ in }
    }
    
    // --- LOGIN AKIŞI ---
    func startInitialFlow() {
        currentState = .askingPermission
        speak(text: "Sesli komutla ilerlemek ister misiniz?")
    }
    
    func speak(text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "tr-TR")
        utterance.rate = 0.5
        speechSynthesizer.speak(utterance)
    }

    // --- ANA SAYFA AKIŞI ---
    func speakAndThen(_ text: String, completion: (() -> Void)? = nil) {
        currentState = .assistantFlow
        self.assistantCompletion = completion
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "tr-TR")
        utterance.rate = 0.5
        assistantSynthesizer.speak(utterance)
    }

    // ORTAK DELEGATE (Hangi synthesizer biterse buraya düşer)
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            if synthesizer == self.assistantSynthesizer {
                self.assistantCompletion?()
                self.onSpeechFinished?() // View'daki bloğu tetikler
            } else {
                // Login Akışı Kontrolü
                switch self.currentState {
                case .askingPermission:
                    self.currentState = .listeningForPermission
                    self.startListening()
                case .askingTC:
                    self.currentState = .listeningForTC
                    self.startListening()
                case .askingPassword:
                    self.currentState = .listeningForPassword
                    self.startListening()
                default: break
                }
            }
        }
    }
    // --- ANA SAYFA VE RANDEVU AKIŞI İÇİN ---
    // Bu metod senin kodundaki speakAndThen ile aynı mantıkta çalışır.
    func assistantSpeak(text: String, completion: (() -> Void)? = nil) {
        // Mevcut akışı durdur (varsa)
        assistantSynthesizer.stopSpeaking(at: .immediate)
        
        currentState = .assistantFlow
        self.assistantCompletion = completion
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "tr-TR")
        utterance.rate = 0.5
        
        // Senin tanımladığın assistantSynthesizer'ı kullanıyoruz
        assistantSynthesizer.speak(utterance)
    }

    // --- DİNLEME MANTIĞI ---
    func startListening() {
        guard !audioEngine.isRunning else { return }
        
        recognitionTask?.cancel()
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true)
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try? audioEngine.start()
        isListening = true
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest!) { result, error in
            if let result = result {
                let text = result.bestTranscription.formattedString.lowercased()
                self.handleRecognizedText(text)
            }
            if error != nil { self.stopListening() }
        }
    }
    
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        isListening = false
    }

    private func handleRecognizedText(_ text: String) {
        // Ana sayfa komutlarını her zaman dışarıya bildir
        self.onCommandRecognized?(text)
        
        switch currentState {
        case .listeningForPermission:
            if text.contains("evet") {
                self.isVoiceModeActive = true // Sesli modu aktifleştir
                stopListening()
                currentState = .askingTC
                speak(text: "Lütfen T.C. kimlik numaranızı söyleyin.")
            }
        case .listeningForTC:
            let digits = text.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            if digits.count >= 11 {
                stopListening()
                onTCDidChange?(String(digits.prefix(11)))
                currentState = .askingPassword
                speak(text: "Lütfen şifrenizi söyleyin.")
            }
        case .listeningForPassword:
            let password = text.replacingOccurrences(of: " ", with: "")
            onPasswordDidChange?(password)
            silenceTimer?.invalidate()
            silenceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                self.stopListening()
                self.onLoginTrigger?()
            }
        default: break
        }
    }
}
