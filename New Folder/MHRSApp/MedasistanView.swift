import AVFoundation
import Speech
import SwiftUI

// MARK: - API Modelleri ve İstemci
struct UserTurn: Encodable {
    let session_id: String
    let user_text: String
    let selected_department: String?
}

struct BotTurn: Decodable {
    let session_id: String
    let next_prompt: String
    let need_more: Bool
    let options: [String]?
    let matched_diseases: [String]
    let user_symptoms: [String]
    let step: String
}

enum DialogAPIError: Error { case invalid(Int), decoding(Error), message(String) }

enum DialogAPI {
    // ---- 1) HOST & PORT (cihaz/sim ayrımı) ----
    #if targetEnvironment(simulator)
    private static let HOST = "http://127.0.0.1"    // Simulator
    #else
    private static let HOST = "http://192.168.1.19" // 
    #endif
    private static let PORT = 8001                  // API hangi portta dinliyorsa 8000/8001

    private static let API_V0 = "\(HOST):\(PORT)/api/v0"
    private static let BASE   = API_V0 + "/medicine" // FastAPI: prefix="/api/v0/medicine"

    // ---- 2) İstek ----
    static func sendTurn(sessionID: String,
                         userText: String,
                         selectedDepartment: String? = nil) async throws -> BotTurn {
        let url = URL(string: "\(BASE)/dialog/turn")!
        print("Dialog URL =>", url.absoluteString)   // Konsolda tam URL’yi gör

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = UserTurn(session_id: sessionID, user_text: userText, selected_department: selectedDepartment)
        req.httpBody = try JSONEncoder().encode(body)

        do {
            let (d, r) = try await URLSession.shared.data(for: req)
            let code = (r as? HTTPURLResponse)?.statusCode ?? -1
            guard (200..<300).contains(code) else {
                if let m = try? JSONDecoder().decode([String:String].self, from: d),
                   let detail = m["detail"] {
                    throw DialogAPIError.message("HTTP \(code): \(detail)")
                }
                throw DialogAPIError.invalid(code)
            }
            return try JSONDecoder().decode(BotTurn.self, from: d)
        } catch let e as URLError {
            throw DialogAPIError.message("URLError \(e.code.rawValue): \(e.localizedDescription)")
        } catch {
            throw error
        }
    }
}

@MainActor
final class MedAsistanSpeech: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var transcript = ""
    @Published var isListening = false
    @Published var isSpeaking  = false
    @Published var sessionID = UUID().uuidString
    @Published var lastBot: BotTurn?
    @Published var errorText: String?

    private let synthesizer = AVSpeechSynthesizer()
    private let audioEngine  = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private lazy var recognizer: SFSpeechRecognizer? = {
        SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
        ?? SFSpeechRecognizer(locale: Locale(identifier: Locale.current.identifier))
        ?? SFSpeechRecognizer()
    }()

    private var finalizeWorkItem: DispatchWorkItem?
    private var finalResultArrived = false
    private var started = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func startFlow() {
        guard !started else { return }
        started = true
        Task { await requestPermissionsAndGreet() }
    }

    private func requestPermissionsAndGreet() async {
        // 1) Mic izni
        let micGranted: Bool
        if #available(iOS 17, *) {
            micGranted = await AVAudioApplication.requestRecordPermission()
        } else {
            micGranted = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
                AVAudioSession.sharedInstance().requestRecordPermission { c.resume(returning: $0) }
            }
        }
        guard micGranted else { self.transcript = "Mikrofon izni gerekli."; return }

        // 2) Speech izni
        let auth = await withCheckedContinuation {
            (c: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard auth == .authorized, recognizer?.isAvailable == true else {
            self.transcript = "Tanıyıcı hazır değil."
            return
        }

        speak("Hoş geldiniz. Ben MedAsistan. Geçmiş olsun, lütfen belirtilerinizi söyleyin.")
    }


    // MARK: - TTS
    func speak(_ text: String) {
        stopListening()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false)
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch { self.errorText = error.localizedDescription }

        let u = AVSpeechUtterance(string: text)
        if let tr = AVSpeechSynthesisVoice(language: "tr-TR") { u.voice = tr }
        isSpeaking = true
        synthesizer.speak(u)
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            if let step = self.lastBot?.step, step == "final" || step == "stopped" { return }

            // playback oturumunu kapat, sonra küçük bekleme ve listen
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? await Task.sleep(nanoseconds: 250_000_000)
            self.beginListening()
        }
    }



    // MARK: - STT
    func beginListening() {
        guard !isListening, !isSpeaking else { return }

        // Eski tap varsa temizle
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        audioEngine.reset()

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.errorText = "Session: \(error.localizedDescription)"
            return
        }

        guard let recognizer, recognizer.isAvailable else {
            self.errorText = "Tanıyıcı uygun değil."
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = false
        req.taskHint = .dictation
        self.request = req

        let input = audioEngine.inputNode
        let hwFormat = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: hwFormat) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            input.removeTap(onBus: 0)
            self.errorText = "Engine: \(error.localizedDescription)"
            return
        }

        isListening = true
        finalResultArrived = false

        task = recognizer.recognitionTask(with: req) { [weak self] result, err in
            guard let self else { return }
            if let t = result?.bestTranscription.formattedString, !t.isEmpty {
                self.transcript = t
            }
            if err != nil || (result?.isFinal ?? false) {
                self.finalResultArrived = true
                self.cancelRecognitionCore()
                Task { await self.sendCurrentTranscript() }
            }
        }
    }


    func finishListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        isListening = false

        finalizeWorkItem?.cancel()
        let wi = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.finalResultArrived == false {
                Task { await self.sendCurrentTranscript() }
                self.cancelRecognitionCore()
            }
        }
        finalizeWorkItem = wi
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: wi)
    }

    func stopListening() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        cancelRecognitionCore()
        audioEngine.reset()
        isListening = false
    }

    private func cancelRecognitionCore() {
        finalizeWorkItem?.cancel(); finalizeWorkItem = nil
        task?.cancel(); task = nil
        request = nil
    }

    // MARK: - Sunucuya gönder
    // MARK: - Sunucuya gönder
        func sendCurrentTranscript() async {
            let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }

            // Sunucuya göndermeden önce dinlemeyi durdur
            self.stopListening()

            do {
                let bot = try await DialogAPI.sendTurn(sessionID: sessionID,
                                                       userText: text,
                                                       selectedDepartment: nil)
                self.lastBot = bot
                self.transcript = ""
                
                // Yeni prompt'u seslendir
                speak(bot.next_prompt)

            } catch {
                self.errorText = (error as NSError).localizedDescription
                speak("Üzgünüm, sunucuya bağlanamadım.")
            }
        }

    func chooseDepartment(_ dep: String) async {
        do {
            let bot = try await DialogAPI.sendTurn(sessionID: sessionID,
                                                   userText: "",
                                                   selectedDepartment: dep)
            self.lastBot = bot
            speak(bot.next_prompt)   // Seçim sonrası da sadece next_prompt
        } catch {
            self.errorText = error.localizedDescription
            speak("Bölüm seçimi gönderilemedi.")
        }
    }
}

struct MedAsistanView: View {
    @StateObject private var vm = MedAsistanSpeech()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Med Asistan").font(.largeTitle).bold()

            if let e = vm.errorText {
                Text(e).foregroundColor(.red)
            }

            // Bot'un son mesajını ekranda göster
            if let bot = vm.lastBot {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Asistan:")
                        .font(.headline)
                    Text(bot.next_prompt)
                        .padding(10)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)

                    // Yeni kısım: Bölüm seçenekleri varsa yatay kaydırılabilir liste
                    if let ops = bot.options, !ops.isEmpty {
                        Text("Bölüm seçenekleri").bold()
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(ops, id: \.self) { o in
                                    Button(o) { Task { await vm.chooseDepartment(o) } }
                                        .buttonStyle(.borderedProminent)
                                        .padding(.vertical, 5) // Dikey boşluk ekleyelim
                                }
                            }
                        }
                    }
                }
            } else {
                Text("Belirtilerinizi söyleyin veya yazın.")
                    .foregroundColor(.secondary)
            }

            TextField("Belirti gir (istiyorsan konuş tuşunu kullan)", text: $vm.transcript)
                .textFieldStyle(.roundedBorder)
            let isTerminal = (vm.lastBot?.step == "final" || vm.lastBot?.step == "stopped")

            HStack {
                Button("Konuş") { vm.beginListening() }
                    .disabled(vm.isSpeaking || vm.isListening || isTerminal)

                Button("Durdur") { vm.finishListening() }
                    .disabled(isTerminal)

                Button("Gönder (yazılı)") { Task { await vm.sendCurrentTranscript() } }
                    .disabled(isTerminal)
            }
            
            Spacer()
        }
        .padding()
        .onAppear { vm.startFlow() }
    }
}/*baş ağrısı denilince tekrar sorma ekle */
