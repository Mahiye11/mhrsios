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

    @State private var showAileHekimiSheet = false
    @State private var shouldStartHomeVoice = true
    @State private var pushVoiceSymptom = false
    @State private var pushProfile = false
    @State private var pushToHastane = false

    @StateObject private var homeVoice = HomeVoiceManager()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                HStack(spacing: 20) {
                    Button {
                        shouldStartHomeVoice = false
                        homeVoice.stopAll()
                        showAileHekimiSheet = true
                    } label: {
                        HomeBigButton(
                            icon: "person.crop.circle.fill",
                            title: "Aile Hekimi\nRandevusu Al",
                            color: .teal
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        print("HASTANE BUTONUNA BASILDI")
                        shouldStartHomeVoice = false
                        homeVoice.stopAll()
                        pushToHastane = true
                    } label: {
                        HomeBigButton(
                            icon: "cross.case.fill",
                            title: "Hastane\nRandevusu Al",
                            color: .red
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)

                Button {
                    shouldStartHomeVoice = false
                    homeVoice.stopAll()
                    pushVoiceSymptom = true
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "mic.fill")
                            .font(.title)

                        Text("Sesli Semptom Anlat")
                            .font(.headline.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(18)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 14) {
                    Text("Randevularınız")
                        .font(.title.bold())
                        .padding(.horizontal)

                    if isLoading {
                        ProgressView("Randevular yükleniyor...")
                            .padding()
                    } else if appointments.isEmpty {
                        Text("Henüz randevunuz bulunmuyor.")
                            .font(.title3)
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                    } else {
                        ForEach(appointments) { appointment in
                            AppointmentCard(appointment: appointment)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.top, 24)
        }
        .navigationTitle("MHRS")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Text(userName.uppercased())
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        shouldStartHomeVoice = false
                        homeVoice.stopAll()
                        pushProfile = true
                    } label: {
                        Label("Profilim", systemImage: "person.fill")
                    }

                    Button(role: .destructive) {
                        shouldStartHomeVoice = false
                        homeVoice.stopAll()
                        dismiss()
                    } label: {
                        Label("Çıkış Yap", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.title)
                        .foregroundColor(.black)
                }
            }
        }
        .navigationDestination(isPresented: $pushVoiceSymptom) {
            VoiceSymptomView()
        }
        .navigationDestination(isPresented: $pushProfile) {
            ProfilView(userId: userId, fallbackName: userName, userTc: userTc)
        }
        .fullScreenCover(isPresented: $pushToHastane) {
            NavigationStack {
                HastaneRandevuView()
            }
        }
        .sheet(isPresented: $showAileHekimiSheet) {
            AileHekimiRandevuView()
        }
        .alert("Hata", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
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

            homeVoice.onManualMode = {
                DispatchQueue.main.async {
                    homeVoice.stopListening()
                }
            }

            homeVoice.onCreateAppointment = {
                DispatchQueue.main.async {
                    shouldStartHomeVoice = false
                    homeVoice.stopAll()
                    pushToHastane = true
                }
            }

            homeVoice.onVoiceSymptom = {
                DispatchQueue.main.async {
                    shouldStartHomeVoice = false
                    homeVoice.stopAll()
                    pushVoiceSymptom = true
                }
            }

            homeVoice.onReadAppointments = {
                DispatchQueue.main.async {
                    readAppointmentsWithVoice()
                }
            }

            shouldStartHomeVoice = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if shouldStartHomeVoice {
                    homeVoice.startInitialFlow()
                }
            }
        }
        .onDisappear {
            shouldStartHomeVoice = false
            homeVoice.stopAll()
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
            print("Randevu hatası:", error.localizedDescription)
            appointments = []
        }
    }

    private func readAppointmentsWithVoice() {
        if appointments.isEmpty {
            homeVoice.speakAndAskCreateAppointment("Randevunuz bulunmamaktadır.")
            return
        }

        var message = "\(userName), randevularınızı okuyorum. "

        for appointment in appointments {
            let clinicName = appointment.doctor?.clinic?.name ?? appointment.doctor?.specialization ?? "Bilinmeyen klinik"
            let doctorName = appointment.doctor?.name ?? "Doktor bilgisi yok"
            message += "\(clinicName), \(doctorName). "
        }

        homeVoice.speakAndAskCreateAppointment(message)
    }
}

struct HomeBigButton: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 46))

            Text(title)
                .font(.title3)
                .multilineTextAlignment(.center)
        }
        .frame(width: 160, height: 120)
        .background(color)
        .foregroundColor(.white)
        .cornerRadius(18)
        .contentShape(Rectangle())
    }
}

// MARK: - Models

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

// MARK: - Appointment Card

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
                    Text(formatDate(date))
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

    private func formatDate(_ rawDate: String) -> String {
        rawDate
            .replacingOccurrences(of: "T", with: " ")
            .replacingOccurrences(of: ".000+00:00", with: "")
    }
}
