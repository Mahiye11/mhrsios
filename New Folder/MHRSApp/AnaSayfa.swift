import SwiftUI
import AVFoundation
import Speech

// MARK: - Voice Manager
class HomeVoiceManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    @Published var isListening = false
    var onSpeechFinished: (() -> Void)?
    var onCommandRecognized: ((String) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "tr-TR")
        utterance.rate = 0.5
        synthesizer.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.onSpeechFinished?()
        }
    }

    func startListening() {
        recognitionTask?.cancel()
        recognitionTask = nil
        
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        audioEngine.prepare()
        try? audioEngine.start()
        
        DispatchQueue.main.async { self.isListening = true }
        
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest!) { result, error in
            if let result = result {
                let transcription = result.bestTranscription.formattedString.lowercased()
                if result.isFinal || transcription.contains("evet") || transcription.contains("hayır") || transcription.contains("aile") || transcription.contains("hastane") {
                    self.stopListening()
                    DispatchQueue.main.async {
                        self.onCommandRecognized?(transcription)
                    }
                }
            }
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        DispatchQueue.main.async { self.isListening = false }
    }
}

// MARK: - Main View
struct AnaSayfa: View {
    @Environment(\.dismiss) var dismiss
    @State private var showAileHekimiSheet = false
    @State private var pushToHastane = false
    @StateObject private var voiceVM = HomeVoiceManager()

    // MARK: - Model
    struct randevu: Identifiable, Hashable {
        let id = UUID()
        let tarih: Date
        let durum: String
        let poliklinik: String
        let hekim: String
        let hastane: String
        let brans: String
    }

    let randevular: [randevu] = [
        randevu(tarih: Date().addingTimeInterval(86400), durum: "Onaylı", poliklinik: "Dahiliye", hekim: "Dr. Ayşe Yılmaz", hastane: "İstanbul Eğitim Hastanesi", brans: "İç Hastalıkları"),
        randevu(tarih: Date().addingTimeInterval(-86400 * 3), durum: "Tamamlandı", poliklinik: "Kardiyoloji", hekim: "Dr. Ahmet Kaya", hastane: "Cerrahpaşa Tıp Fakültesi", brans: "Kalp Damar"),
        randevu(tarih: Date().addingTimeInterval(-86400 * 6), durum: "Geçmiş Randevu", poliklinik: "Kalp ve Damar Cerrahisi", hekim: "Dr. Orhan Kaya", hastane: " Farabi Fakültesi", brans: "Kalp Damar")
    ]

    var body: some View {
        VStack {
            // Gizli Navigasyon Bağlantısı
            NavigationLink(destination: HastaneRandevuView(), isActive: $pushToHastane) { EmptyView() }
            
            ScrollView {
                VStack(spacing: 20) {
                    // Randevu Alma Butonları
                    HStack(spacing: 20) {
                        Button(action: {
                            showAileHekimiSheet = true
                        }) {
                            VStack {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 40))
                                Text("Aile Hekimi Randevusu Al")
                            }
                            .frame(width: 160, height: 120)
                            .background(voiceVM.isListening ? Color.orange : Color.teal)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }

                        Button(action: {
                            pushToHastane = true
                        }) {
                            VStack {
                                Image(systemName: "cross.case.fill")
                                    .font(.system(size: 40))
                                Text("Hastane Randevusu Al")
                                    .multilineTextAlignment(.center)
                            }
                            .frame(width: 160, height: 120)
                            .background(voiceVM.isListening ? Color.orange : Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }

                    // Randevu Listesi Bileşeni
                    RandevuListesi()
                        .frame(height: 800)

                    Spacer()
                }
                .padding()
            }
        }
        .navigationTitle("MHRS")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(trailing:
            Text("MAHİYE ZEYNEP BAYRAM")
                .font(.subheadline)
                .foregroundColor(.gray)
        )
        .sheet(isPresented: $showAileHekimiSheet) {
            AileHekimiView()
        }
        .onAppear {
            runAssistantScenario()
        }
    }

    // MARK: - Sesli Asistan Senaryosu
    private func runAssistantScenario() {
        let iptalMesaji = "25 Şubat günü saat 20 36'da kardiyoloji bölümü Ankara şehir hastanesinde randevunuz iptal edilmiştir. Yeni bir randevu almak ister misiniz?"
        
        // 1. Randevu bilgisini oku
        voiceVM.speak(iptalMesaji)
        
        // 2. Konuşma bitince "Evet/Hayır" için dinle
        voiceVM.onSpeechFinished = {
            voiceVM.startListening()
        }
        
        // 3. Cevabı işle
        voiceVM.onCommandRecognized = { command in
            print("Gelen Komut: \(command)")
            
            if command.contains("evet") {
                voiceVM.speak("Aile hekimi randevusu mu, yoksa hastane randevusu mu istersiniz?")
                
                // İkinci aşama dinlemesi
                voiceVM.onSpeechFinished = {
                    voiceVM.startListening()
                    voiceVM.onCommandRecognized = { subCommand in
                        if subCommand.contains("aile") {
                            voiceVM.speak("Aile hekimi randevu sayfasını açıyorum.")
                            showAileHekimiSheet = true
                        } else if subCommand.contains("hastane") {
                            voiceVM.speak("Hastane randevu sayfasına yönlendiriyorum.")
                            pushToHastane = true
                        }
                    }
                }
            } else if command.contains("hayır") {
                voiceVM.speak("Giriş ekranına dönülüyor.")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Preview
struct AnaSayfa_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            AnaSayfa()
        }
    }
}
