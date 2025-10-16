import SwiftUI

struct RandevuOlusturAileHekimiView: View {
    @Environment(\.dismiss) var dismiss
    
    @State private var secilenTarih = Date()
    @State private var secilenSaat = ""
    
    let saatler = ["08:00", "08:30", "09:00", "09:30", "10:00", "10:30", "11:00", "11:30",
                   "13:00", "13:30", "14:00", "14:30", "15:00", "15:30", "16:00", "16:30"]

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Group {
                    Label("EMRE KOÇ", systemImage: "person.crop.circle")
                    Label("İZMİR BUCA 4 NOLU MERKEZ AİLE SAĞLIĞI MERKEZİ", systemImage: "building.columns")
                    Label("İZMİR BUCA 018 NOLU AİLE HEKİMLİĞİ BİRİMİ", systemImage: "heart.text.square")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

                Divider()
                
                DatePicker("Gün Seçin", selection: $secilenTarih, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .padding(.horizontal)
                
                Picker("Saat Seçin", selection: $secilenSaat) {
                    ForEach(saatler, id: \.self) {
                        Text($0)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)

                // Onay Butonu
                Button(action: {
                    print("Randevu Oluşturuldu: \(secilenTarih) - \(secilenSaat)")
                    dismiss()
                }) {
                    Text("Tarihi Onayla ve Randevu Oluştur")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.top)

                Spacer()
                
                Button("Kapat") {
                    dismiss()
                }
                .foregroundColor(.red)
                .padding(.bottom)
            }
            .navigationTitle("Randevu Oluştur")
            .padding()
        }
    }
}
