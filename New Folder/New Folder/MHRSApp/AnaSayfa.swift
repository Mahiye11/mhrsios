import SwiftUI
import AVFoundation
import Speech

struct AnaSayfa: View {
    let userId: Int
    let userName: String
    let userTc: String

    @State private var appointments: [AppointmentDTO] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var pushToHastane = false
    @State private var showAileHekimiSheet = false

    @StateObject private var homeVoice = HomeVoiceManager()
    
    @Environment(\.dismiss) private var dismiss
    @State private var showMenu = false
    @State private var pushProfile = false

    var body: some View {
        VStack {
            ScrollView {
                VStack(spacing: 24) {

                    HStack(spacing: 20) {
                        Button {
                            showAileHekimiSheet = true
                        } label: {
                            VStack {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 42))

                                Text("Aile Hekimi\nRandevusu Al")
                                    .multilineTextAlignment(.center)
                            }
                            .frame(width: 160, height: 120)
                            .background(Color.teal)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                        }
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Text(userName.uppercased())
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }

                            ToolbarItem(placement: .topBarTrailing) {
                                Menu {
                                    Button {
                                        pushProfile = true
                                    } label: {
                                        Label("Profilim", systemImage: "person.fill")
                                    }

                                    Button(role: .destructive) {
                                        dismiss()
                                    } label: {
                                        Label("Çıkış Yap", systemImage: "rectangle.portrait.and.arrow.right")
                                    }
                                } label: {
                                    Image(systemName: "line.3.horizontal")
                                        .font(.title2)
                                        .foregroundColor(.black)
                                }
                            }
                        }

                        Button {
                            pushToHastane = true
                        } label: {
                            VStack {
                                Image(systemName: "cross.case.fill")
                                    .font(.system(size: 42))

                                Text("Hastane\nRandevusu Al")
                                    .multilineTextAlignment(.center)
                            }
                            .frame(width: 160, height: 120)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(16)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Randevularınız")
                            .font(.title2.bold())
                            .padding(.horizontal)

                        if isLoading {
                            ProgressView("Randevular yükleniyor...")
                                .padding()
                        } else if appointments.isEmpty {
                            Text("Henüz randevunuz bulunmuyor.")
                                .foregroundColor(.gray)
                                .padding()
                        } else {
                            ForEach(appointments) { appointment in
                                AppointmentCard(appointment: appointment)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.top, 20)
            }
        }
        .navigationTitle("MHRS")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text(userName.uppercased())
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
        .navigationDestination(isPresented: $pushToHastane) {
            Text("Hastane Randevu Sayfası")
        }
        .navigationDestination(isPresented: $pushProfile) {
            ProfilView(userId: userId, fallbackName: userName, userTc: userTc)
        }
        .sheet(isPresented: $showAileHekimiSheet) {
            Text("Aile Hekimi Randevu Sayfası")
        }
        .alert("Hata", isPresented: .constant(errorMessage != nil)) {
            Button("Tamam") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            Task {
                await fetchAppointments()
            }

            homeVoice.onReadAppointments = {
                readAppointmentsWithVoice()
            }

            homeVoice.onCreateAppointment = {
                pushToHastane = true
            }

            homeVoice.startInitialFlow()
        }
    }

    @MainActor
    private func fetchAppointments() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let url = URL(string: "\(APIConfig.baseURL)/api/appointments/user/\(userId)")!
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "Sunucu cevabı okunamadı."
                return
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                errorMessage = String(data: data, encoding: .utf8) ?? "Randevular alınamadı."
                return
            }

            appointments = try JSONDecoder().decode([AppointmentDTO].self, from: data)

        } catch {
            errorMessage = "Randevu bağlantı hatası: \(error.localizedDescription)"
        }
    }

    private func readAppointmentsWithVoice() {
        if appointments.isEmpty {
            homeVoice.speakAndAskCreateAppointment("Randevunuz bulunmamaktadır. Yeni bir randevu oluşturmak ister misiniz?")
            return
        }

        var message = "\(userName), randevularınızı okuyorum. "

        for appointment in appointments {
            let clinicName = appointment.doctor?.clinic?.name ?? appointment.doctor?.specialization ?? "Bilinmeyen klinik"
            let doctorName = appointment.doctor?.name ?? "Doktor bilgisi yok"
            let status = appointment.status ?? "Durum bilgisi yok"

            message += "\(clinicName), \(doctorName), durum: \(status). "
        }

        message += "Randevu oluşturmak ister misiniz?"
        homeVoice.speakAndAskCreateAppointment(message)
    }
}
struct AppointmentDTO: Identifiable, Codable {
    let id: Int
    let appointmentDateTime: String?
    let status: String?
    let doctor: DoctorDTO?
    let user: AppointmentUserDTO?
}
struct DoctorDTO: Codable, Hashable {
    let id: Int?
    let name: String?
    let specialization: String?
    let clinic: ClinicDTO?
}
struct ClinicDTO: Codable, Hashable {
    let id: Int?
    let name: String?
    let location: String?
}
struct AppointmentUserDTO: Codable, Hashable {
    let id: Int?
    let name: String?
    let surname: String?
    let tcKimlik: String?
}
struct AppointmentCard: View {
    let appointment: AppointmentDTO

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(appointment.doctor?.clinic?.name ?? appointment.doctor?.specialization ?? "Klinik bilgisi yok")
                    .font(.headline)

                Text(appointment.doctor?.name ?? "Doktor bilgisi yok")
                    .font(.subheadline)

                if let date = appointment.appointmentDateTime {
                    Text(date)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            Text(appointment.status ?? "Bilinmiyor")
                .font(.caption)
                .padding(8)
                .background(Color.blue.opacity(0.12))
                .cornerRadius(8)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
    }
}
