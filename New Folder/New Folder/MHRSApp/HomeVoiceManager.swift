//
//  HomeVoiceManager.swift
//  MHRSApp
//
//  Created by Mahiye Zeynep Bayram on 1.05.2026.
//
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
        case askingCreateAfterRead
        case listeningCreateAfterRead
    }

    @Published var isListening = false

    var onReadAppointments: (() -> Void)?
    var onCreateAppointment: (() -> Void)?

    private var step: Step = .idle

    private let synthesizer = AVSpeechSynthesizer()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    override init() {
        super.init()
        synthesizer.delegate = self

        SFSpeechRecognizer.requestAuthorization { _ in }
        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
    }

    func startInitialFlow() {
        step = .askingVoicePermission
        speak("Sesli devam etmek ister misiniz?")
    }

    func speak(_ text: String) {
        stopListening()

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
        try? session.setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "tr-TR")
        synthesizer.speak(utterance)
    }

    func speakAndAskCreateAppointment(_ text: String) {
        step = .askingCreateAfterRead
        speak(text)
    }

    func speakAndReturnToMenu(_ text: String) {
        step = .askingCreateAfterRead
        speak(text)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        switch step {
        case .askingVoicePermission:
            step = .listeningVoicePermission
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.startListening()
            }

        case .askingMainChoice:
            step = .listeningMainChoice
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.startListening()
            }

        case .askingCreateAfterRead:
            step = .listeningCreateAfterRead
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.startListening()
            }

        default:
            break
        }
    }

    private func startListening() {
        stopListening()

        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true)
        } catch {
            print("Audio session hata:", error.localizedDescription)
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }

        recognitionRequest.shouldReportPartialResults = true
        
        let inputNode = audioEngine.inputNode
        let format = inputNode.inputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            print("Mikrofon formatı geçersiz")
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
        } catch {
            print("Audio engine hata:", error.localizedDescription)
            return
        }

        recognitionTask = recognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result {
                let text = result.bestTranscription.formattedString.lowercased()
                print("AnaSayfa algılanan:", text)

                if text.contains("evet") ||
                    text.contains("hayır") ||
                    text.contains("hayir") ||
                    text.contains("randevu") ||
                    text.contains("randevular") ||
                    text.contains("oku") ||
                    text.contains("oluştur") ||
                    text.contains("olustur") {

                    self.handle(text)
                }
            }

            if error != nil {
                self.stopListening()
            }
        }
    }

    func stopListening() {
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

    private func handle(_ text: String) {
        switch step {

        case .listeningVoicePermission:
            if text.contains("evet") {
                stopListening()
                step = .askingMainChoice
                speak("Randevularınızı okumamı mı istersiniz, yoksa randevu oluşturmak mı istersiniz?")
            } else if text.contains("hayır") || text.contains("hayir") {
                stopListening()
                step = .idle
                speak("Tamam, sayfadan manuel devam edebilirsiniz.")
            }

        case .listeningMainChoice:
            if text.contains("oku") || text.contains("randevular") || text.contains("randevularımı") {
                stopListening()
                step = .idle
                onReadAppointments?()
            } else if text.contains("oluştur") || text.contains("olustur") || text.contains("almak") {
                stopListening()
                step = .idle
                onCreateAppointment?()
            } else {
                stopListening()
                step = .askingMainChoice
                speak("Anlayamadım. Randevularınızı okumamı mı istersiniz, yoksa randevu oluşturmak mı istersiniz?")
            }

        case .listeningCreateAfterRead:
            if text.contains("evet") {
                stopListening()
                step = .idle
                onCreateAppointment?()
            } else if text.contains("hayır") || text.contains("hayir") {
                stopListening()
                step = .askingMainChoice
                speak("Peki. Randevularınızı okumamı mı istersiniz, yoksa randevu oluşturmak mı istersiniz?")
            }

        default:
            break
        }
    }
}
