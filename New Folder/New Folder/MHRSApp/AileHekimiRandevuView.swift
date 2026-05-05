import SwiftUI

struct AileHekimiRandevuView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var showRandevuView = false
    @State private var selectedType = ""

    let doctorName = "EMRE KOÇ"
    let healthCenter = "İZMİR BUCA 4 NOLU MERKEZ AİLE SAĞLIĞI MERKEZİ"
    let unitName = "İZMİR BUCA 018 NOLU AİLE HEKİMLİĞİ BİRİMİ"
    let address = "YAYLACIK MAHALLESİ 178 SOKAK"

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Geri")
                    }
                    .foregroundColor(.blue)
                }

                Spacer()
            }

            Text("Aile Hekimi Randevu Al")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 14) {
                InfoRow(icon: "person.crop.circle", text: doctorName)
                InfoRow(icon: "building.columns", text: healthCenter)
                InfoRow(icon: "heart.circle", text: unitName)
                InfoRow(icon: "mappin.and.ellipse", text: address)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .cornerRadius(18)
            .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)

            VStack(spacing: 12) {
                Button {
                    selectedType = "Aile Hekimi Muayene"
                    showRandevuView = true
                } label: {
                    Label("Aile Hekimi Muayene", systemImage: "stethoscope")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }

                Button {
                    selectedType = "Aile Hekimi Tarama"
                    showRandevuView = true
                } label: {
                    Label("Aile Hekimi Tarama", systemImage: "waveform.path.ecg")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.85))
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showRandevuView) {
            AileHekimiRandevuOlusturView(
                appointmentType: selectedType,
                doctorName: doctorName,
                healthCenter: healthCenter
            )
        }
    }
}

struct InfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)

            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)

            Spacer()
        }
    }
}

struct AileHekimiRandevuOlusturView: View {
    @Environment(\.dismiss) private var dismiss

    let appointmentType: String
    let doctorName: String
    let healthCenter: String

    @State private var selectedDate = Date()
    @State private var selectedTime = "09:00"
    @State private var showAlert = false

    let times = [
        "09:00", "09:30", "10:00", "10:30",
        "11:00", "11:30", "13:00", "13:30",
        "14:00", "14:30", "15:00", "15:30"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(appointmentType)
                        .font(.title2.bold())

                    Text(doctorName)
                        .font(.headline)
                        .foregroundColor(.blue)

                    Text(healthCenter)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.white)
                .cornerRadius(18)

                DatePicker(
                    "Tarih Seç",
                    selection: $selectedDate,
                    in: Date()...Calendar.current.date(byAdding: .day, value: 14, to: Date())!,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                .background(Color.white)
                .cornerRadius(18)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                    ForEach(times, id: \.self) { time in
                        Button {
                            selectedTime = time
                        } label: {
                            Text(time)
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(selectedTime == time ? Color.red : Color.white)
                                .foregroundColor(selectedTime == time ? .white : .blue)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(selectedTime == time ? Color.red : Color.blue, lineWidth: 1.5)
                                )
                                .cornerRadius(14)
                        }
                    }
                }

                Button {
                    showAlert = true
                } label: {
                    Text("Randevuyu Onayla")
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(
                            LinearGradient(
                                colors: [.blue, .red.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(18)
                }

                Spacer()
            }
            .padding()
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Randevu Oluştur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Kapat") {
                        dismiss()
                    }
                }
            }
            .alert("Randevu Oluşturuldu", isPresented: $showAlert) {
                Button("Tamam") {
                    dismiss()
                }
            } message: {
                Text("\(appointmentType)\n\(selectedTime) için randevunuz oluşturuldu.")
            }
        }
    }
}
