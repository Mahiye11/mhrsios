import SwiftUI

struct AnaSayfa: View {
    @State private var showAileHekimiSheet = false
  

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
        NavigationView {
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
                            .background(Color.teal)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .sheet(isPresented: $showAileHekimiSheet) {
                            AileHekimiView()
                        }

                        NavigationLink(destination: HastaneRandevuView()) {
                            VStack {
                                Image(systemName: "cross.case.fill")
                                    .font(.system(size: 40))
                                Text("Hastane Randevusu Al")
                                    .multilineTextAlignment(.center)
                            }
                            .frame(width: 160, height: 120)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }

                
                    RandevuListesi()
                        .frame(height: 800)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("MHRS")
            .navigationBarItems(trailing:
                Text("MAHİYE ZEYNEP BAYRAM")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            )
        }
    }
}
struct AnalysisResult: Codable {
    let raw_text: String
    let symptoms: [String]
    let rule_based_diseases: [String]
    let ml_prediction: String
    let departments: [String]
}

import Foundation

func analyzeVoice(url: URL) async throws -> AnalysisResult {
    let endpoint = URL(string: "http://127.0.0.1:8000/analyze")!
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"

    let boundary = UUID().uuidString
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    var data = Data()
    data.append("--\(boundary)\r\n".data(using: .utf8)!)
    data.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
    data.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
    data.append(try Data(contentsOf: url))
    data.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

    let (responseData, _) = try await URLSession.shared.upload(for: request, from: data)
    return try JSONDecoder().decode(AnalysisResult.self, from: responseData)
}

