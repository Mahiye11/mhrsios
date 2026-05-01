/*import SwiftUI

struct RandevuOluşturAileHekimiView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var voiceVM: VoiceManager
    
    @State private var secilenTarih = Date()
    @State private var secilenSaat = ""
    @State private var isConfirmed = false
    
    let saatler = ["08:00", "08:30", "09:00", "09:30", "10:00", "10:30", "11:00", "11:30",
                   "13:00", "13:30", "14:00", "14:30", "15:00", "15:30", "16:00", "16:30"]

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("EMRE KOÇ", systemImage: "person.crop.circle")
                    Label("İZMİR BUCA 4 NOLU MERKEZ ASM", systemImage: "building.columns")
                    Label("İZMİR BUCA 018 NOLU AİLE HEKİMLİĞİ", systemImage: "heart.text.square")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .font(.subheadline)

                Divider()
                
                DatePicker("Gün Seçin", selection: $secilenTarih, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .padding(.horizontal)
                
                VStack(alignment: .leading) {
                    Text("Saat Seçin")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                    
                    Picker("Saat Seçin", selection: $secilenSaat) {
                        if secilenSaat.isEmpty {
                            Text("Lütfen bir saat seçin").tag("")
                        }
                        ForEach(saatler, id: \.self) { saat in
                            Text(saat).tag(saat)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                }

                Button(action: {
                    tamamlaVeKapat()
                }) {
                    Text(isConfirmed ? "Randevu Oluşturuldu" : "Tarihi Onayla ve Randevu Oluştur")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(secilenSaat.isEmpty ? Color.gray : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .disabled(secilenSaat.isEmpty || isConfirmed)

                Spacer()
                
                Button("Kapat") {
                    voiceVM.stopListening()
                    dismiss()
                }
                .foregroundColor(.red)
            }
            .navigationTitle("Randevu Oluştur")
            .padding()
            .onAppear {
                if voiceVM.isVoiceModeActive {
                    baslatSesliRehber()
                }
            }
        }
    }

    private func baslatSesliRehber() {
        voiceVM.assistantSpeak(text: "Hangi gün ve saatte randevu istersiniz?") {
            voiceVM.startListening()
        }
        
        voiceVM.onCommandRecognized = { text in
            for saat in saatler {
                let okunabilirSaat = saat.replacingOccurrences(of: ":00", with: " ").replacingOccurrences(of: ":30", with: " buçuk")
                
                if text.contains(saat.replacingOccurrences(of: ":", with: " ")) || text.contains(okunabilirSaat) {
                    self.secilenSaat = saat
                    voiceVM.assistantSpeak(text: "\(saat) saatini seçtiniz. Onaylıyor musunuz?") {
                        voiceVM.startListening()
                    }
                }
            }
            
            if text.contains("evet") || text.contains("onaylıyorum") {
                if !secilenSaat.isEmpty {
                    tamamlaVeKapat()
                }
            }
        }
    }
    
    private func tamamlaVeKapat() {
        isConfirmed = true
        if voiceVM.isVoiceModeActive {
            voiceVM.assistantSpeak(text: "Randevunuz oluşturulmuştur. Geçmiş olsun.") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    dismiss()
                }
            }
        } else {
            dismiss()
        }
    }
}
*/
