//
//  RegisterModeVoiceManager.swift
//  MHRSApp
//
//  Created by Mahiye Zeynep Bayram on 1.05.2026.
//
import Foundation
import Speech
import AVFoundation

final class RegisterModeVoiceManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    var onManualSelected: (() -> Void)?
    var onVoiceSelected: (() -> Void)?

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

    func start() {
        speak("Manuel mi, sesli mi kayıt olmak istersiniz?")
    }

    private func speak(_ text: String) {
        stopListening()

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
        try? session.setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "tr-TR")
        synthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.startListening()
        }
    }

    private func startListening() {
        stopListening()

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest else { return }

        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let format = inputNode.inputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else { return }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try? audioEngine.start()

        recognitionTask = recognizer?.recognitionTask(with: recognitionRequest) { result, error in
            if let result {
                let text = result.bestTranscription.formattedString.lowercased()
                print("Kayıt tipi:", text)

                if text.contains("manuel") || text.contains("elle") {
                    self.stopListening()
                    self.onManualSelected?()
                } else if text.contains("sesli") || text.contains("ses") {
                    self.stopListening()
                    self.onVoiceSelected?()
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
    }
}
