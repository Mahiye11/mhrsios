import SwiftUI
import AVFoundation
import Speech

struct AnaSayfa: View {
    @Environment(\.dismiss) var dismiss
    @State private var showAileHekimiSheet = false
    @State private var pushToHastane = false
    @StateObject private var voiceVM = VoiceManager()

    // ASİSTANIN HANGİ AŞAMADA OLDUĞUNU TAKİP EDEN YAPI
    enum AssistantStep {
        case initial        // "Yeni randevu ister misiniz?" aşaması
        case choosingType   // "Aile mi hastane mi?" aşaması
        case idle           // Bekleme veya süreç dışı
    }
    
    @State private var currentStep: AssistantStep = .idle

    // MARK: - Model
    struct Randevu: Identifiable, Hashable {
        let id = UUID()
        let tarih: Date
        let durum: String
        let poliklinik: String
        let hekim: String
        let hastane: String
        let brans: String
    }

    let randevular: [Randevu] = [
        Randevu(tarih: Date().addingTimeInterval(86400), durum: "Onaylı", poliklinik: "Dahiliye", hekim: "Dr. Ayşe Yılmaz", hastane: "İstanbul Eğitim Hastanesi", brans: "İç Hastalıkları"),
        Randevu(tarih: Date().addingTimeInterval(-86400 * 3), durum: "Tamamlandı", poliklinik: "Kardiyoloji", hekim: "Dr. Ahmet Kaya", hastane: "Cerrahpaşa Tıp Fakültesi", brans: "Kalp Damar"),
        Randevu(tarih: Date().addingTimeInterval(-86400 * 6), durum: "Geçmiş Randevu", poliklinik: "Kalp ve Damar Cerrahisi", hekim: "Dr. Orhan Kaya", hastane: "Farabi Fakültesi", brans: "Kalp Damar")
    ]

    var body: some View {
        VStack {
            // Navigasyon Bağlantısı (voiceVM buraya da aktarılabilir)
            //NavigationLink(destination: Text("Hastane Randevu Sayfası"), isActive: $pushToHastane) { EmptyView() }
            
            ScrollView {
                VStack(spacing: 20) {
                    HStack(spacing: 20) {
                        // Aile Hekimi Butonu
                        Button(action: { showAileHekimiSheet = true }) {
                            VStack {
                                Image(systemName: "person.crop.circle.fill").font(.system(size: 40))
                                Text("Aile Hekimi\nRandevusu Al")
                            }
                            .frame(width: 160, height: 120)
                            .background(voiceVM.isListening && currentStep == .choosingType ? Color.orange : Color.teal)
                            .foregroundColor(.white).cornerRadius(12)
                        }

                        // Hastane Butonu
                        Button(action: { pushToHastane = true }) {
                            VStack {
                                Image(systemName: "cross.case.fill").font(.system(size: 40))
                                Text("Hastane\nRandevusu Al").multilineTextAlignment(.center)
                            }
                            .frame(width: 160, height: 120)
                            .background(voiceVM.isListening && currentStep == .choosingType ? Color.orange : Color.red)
                            .foregroundColor(.white).cornerRadius(12)
                        }
                    }

                    // Randevu Listesi Görünümü (Temsili)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Randevularınız").font(.headline).padding(.horizontal)
                        ForEach(randevular, id: \.self) { r in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(r.poliklinik).bold()
                                    Text(r.hastane).font(.caption)
                                }
                                Spacer()
                                Text(r.durum).font(.caption).padding(5).background(Color.blue.opacity(0.1)).cornerRadius(5)
                            }
                            .padding()
                            .background(Color.white)
                            .cornerRadius(10)
                            .shadow(radius: 1)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("MHRS")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarItems(trailing: Text("ZEYNEP BAYRAM").font(.subheadline).foregroundColor(.gray))
        .sheet(isPresented: $showAileHekimiSheet) {
            // VoiceManager'ı alt sayfaya aktarıyoruz
          //  AileHekimiRandevuView(voiceVM: voiceVM)
        }
        .onAppear {
            // Sayfa açıldığında senaryoyu başlat
           // runAssistantScenario()
        }
    }

  /*  // MARK: - Sesli Senaryo Akışı
    private func runAssistantScenario() {
        let dinamikMesaj = tumRandevulariSeslendir()
        currentStep = .initial
        
        // 1. Önce randevuları oku ve yeni randevu isteyip istemediğini sor
        voiceVM.speakAndThen(dinamikMesaj) {
            // Konuşma bittiğinde dinlemeye başla
            voiceVM.startListening()
        }
        
        // 2. Gelen cevapları dinle
        voiceVM.onCommandRecognized = { command in
            let text = command.lowercased()
            
            switch currentStep {
            case .initial:
                if text.contains("evet") || text.contains("istiyorum") {
                    voiceVM.stopListening() // Önce durdur
                    currentStep = .choosingType // Adımı güncelle
                    
                    // İkinci soruyu sor
                    voiceVM.speakAndThen("Anlaşıldı. Aile hekimi mi, yoksa hastane randevusu mu oluşturmak istersiniz?") {
                        voiceVM.startListening() // Soru bitince tekrar dinle
                    }
                } else if text.contains("hayır") {
                    voiceVM.stopListening()
                    currentStep = .idle
                    voiceVM.speak(text: "Peki Zeynep Hanım, sağlıklı günler dilerim.")
                }

            case .choosingType:
                if text.contains("aile") {
                    voiceVM.stopListening()
                    currentStep = .idle
                    self.showAileHekimiSheet = true
                } else if text.contains("hastane") {
                    voiceVM.stopListening()
                    currentStep = .idle
                    self.pushToHastane = true
                }
                
            case .idle:
                break
            }
        }
    }

    // Mesaj Oluşturucu
    private func tumRandevulariSeslendir() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr-TR")
        formatter.dateFormat = "d MMMM"
        
        var mesaj = "Merhaba Zeynep Hanım. "
        
        if let onayli = randevular.first(where: { $0.durum == "Onaylı" }) {
            let t = formatter.string(from: onayli.tarih)
            mesaj += "\(t) tarihindeki \(onayli.poliklinik) randevunuz onaylanmıştır. "
        }
        
        mesaj += "Yeni bir randevu oluşturmak ister misiniz?"
        return mesaj
    }
   */
}

