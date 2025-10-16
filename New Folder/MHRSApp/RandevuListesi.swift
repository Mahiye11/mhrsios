import SwiftUI
import Foundation
struct Randevu: Identifiable, Hashable {
    let id = UUID()
    let tarih: Date
    let durum: String
    let poliklinik: String
    let hekim: String
    let hastane: String
    let brans: String
}

struct RandevuListesi: View {
    @State private var selectedTab = 0
    @State private var randevular: [Randevu] = [
        Randevu(
            tarih: Date(),
            durum: "Onaylı",
            poliklinik: "Dahiliye",
            hekim: "Dr. Ahmet Yılmaz",
            hastane: "Ankara Şehir Hastanesi",
            brans: "İç Hastalıkları"
        ),
        Randevu(
            tarih: Date().addingTimeInterval(86400),
            durum: "İptal Randevu",
            poliklinik: "Kardiyoloji",
            hekim: "Dr. Ayşe Demir",
            hastane: "Ankara Şehir Hastanesi",
            brans: "Kalp ve Damar"
        )
    ]
    
    var filteredRandevular: [Randevu] {
        let now = Date()
        return randevular
            .filter { selectedTab == 0 ? $0.tarih >= now : $0.tarih < now }
            .sorted { $0.tarih < $1.tarih }
    }
    
    var body: some View {
        List {
            ForEach(filteredRandevular) { randevu in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(randevu.tarih, style: .date)
                        Text(randevu.tarih, style: .time)
                    }
                    .font(.headline)
                    
                    Text(randevu.durum)
                        .foregroundColor(randevu.durum == "İptal Randevu" ? .red : .green)
                    
                    Text(randevu.poliklinik).bold()
                    Text(randevu.hekim)
                    Text(randevu.hastane).font(.subheadline)
                    Text(randevu.brans).foregroundColor(.gray)
                }
                .padding(.vertical, 8)
            }
        }
        .navigationTitle("Randevularım")
    }
}
