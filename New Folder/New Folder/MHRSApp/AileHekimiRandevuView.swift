import SwiftUI

struct AileHekimiRandevuView: View {
    @State private var showRandevuView = false
    @Environment(\.dismiss) var dismiss
    // ÖNEMLİ: @StateObject değil @ObservedObject kullanıyoruz ki önceki sayfadaki "Evet" tercihi buraya gelsin.
    @ObservedObject var voiceVM: VoiceManager

    var body: some View {
        VStack(spacing: 20) {
            Text("Aile Hekimi Randevu Al")
                .font(.title2)
                .bold()
                .padding(.top)

            Group {
                Label("EMRE KOÇ", systemImage: "person.crop.circle")
                Label("İZMİR BUCA 4 NOLU MERKEZ AİLE SAĞLIĞI MERKEZİ", systemImage: "building.columns")
                Label("İZMİR BUCA 018 NOLU AİLE HEKİMLİĞİ BİRİMİ", systemImage: "heart.circle")
                Label("YAYLACIK MAHALLESİ 178 SOKAK", systemImage: "mappin.and.ellipse")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .foregroundColor(.primary)

            Divider()

            // SENİN BUTON TASARIMIN
            VStack(spacing: 12) {
                Button {
                    showRandevuView = true
                } label: {
                    Label("Aile Hekimi Muayene", systemImage: "stethoscope")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.teal)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                Button {
                    showRandevuView = true
                } label: {
                    Label("Aile Hekimi Tarama", systemImage: "waveform.path.ecg")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.teal.opacity(0.7)) // Farklılaştırmak için
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
            }

            Spacer()

            Button("Kapat") {
                voiceVM.stopListening()
                dismiss()
            }
            .foregroundColor(.red)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .padding()
        .sheet(isPresented: $showRandevuView) {
            // Bir sonraki sayfaya VoiceManager'ı paslıyoruz
            RandevuOluşturAileHekimiView(voiceVM: voiceVM)
        }
        .onAppear {
            // GİRİŞTE EVET DEDİYSE SESLİ AKIŞ BAŞLAR
            if voiceVM.isVoiceModeActive {
                startAssistantFlow()
            }
        }
    }

    private func startAssistantFlow() {
        voiceVM.assistantSpeak(text: "Aile hekimi randevusu oluşturalım mı?") {
            voiceVM.startListening()
        }
        
        voiceVM.onCommandRecognized = { text in
            if text.contains("evet") {
                voiceVM.stopListening()
                self.showRandevuView = true
            } else if text.contains("hayır") {
                voiceVM.stopListening()
                voiceVM.assistantSpeak(text: "Anlaşıldı, ana sayfaya dönüyorum.") {
                    dismiss() // Hayır derse ana sayfaya atar
                }
            }
        }
    }
}
