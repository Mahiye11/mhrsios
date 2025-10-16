import SwiftUI

struct AileHekimiView: View {
    @State private var showRandevuView = false
    @Environment(\.dismiss) var dismiss

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
            .sheet(isPresented: $showRandevuView) {
                RandevuOlusturAileHekimiView()
            }
            Button {
                showRandevuView = true
            } label: {
                Label("Aile Hekimi Tarama", systemImage: "waveform.path.ecg")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.teal)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .sheet(isPresented: $showRandevuView) {
                RandevuOlusturAileHekimiView()
            }

            Button {
                showRandevuView = true
            } label: {
                Label("Aile Hekimi Uzaktan Değerlendirme", systemImage: "bubble.left.and.bubble.right.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.teal)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .sheet(isPresented: $showRandevuView) {
                RandevuOlusturAileHekimiView()
            }
          
            Spacer()

            Button("Kapat") {
                dismiss()
            }
            .foregroundColor(.red)
            .padding(.top)
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(16)
        .padding()
    }
}
