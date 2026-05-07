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
    
    private let mainMenuPrompt = "Hastane randevusu mu, aile hekimi randevusu mu, sesli semptom analizi mi, profil bilgilerinizi güncellemek mi istersiniz, yoksa randevularınızı mı okumak istersiniz?"


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
                            AppointmentCard(
                                appointment: appointment,
                                onCancel: {
                                    Task {
                                        await deleteAppointment(appointment)
                                    }
                                }
                            )
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
            VoiceSymptomView(userId: userId)
        }
        .navigationDestination(isPresented: $pushProfile) {
            ProfilView(userId: userId, fallbackName: userName, userTc: userTc)
        }
        .onChange(of: pushVoiceSymptom) { _, isPresented in
            if !isPresented {
                restartHomeVoiceFlowAfterReturn()
            }
        }
        .onChange(of: pushProfile) { _, isPresented in
            if !isPresented {
                restartHomeVoiceFlowAfterReturn()
            }
        }
        .fullScreenCover(isPresented: $pushToHastane, onDismiss: {
            Task {
                await fetchAppointments()
                await MainActor.run {
                    restartHomeVoiceFlowAfterReturn()
                }
            }
        }) {
            NavigationStack {
                HastaneRandevuView(userId: userId, initialClinic: nil)
            }
        }
        .sheet(isPresented: $showAileHekimiSheet, onDismiss: {
            Task {
                await fetchAppointments()
                await MainActor.run {
                    restartHomeVoiceFlowAfterReturn()
                }
            }
        }) {
            AileHekimiRandevuView(userId: userId, startWithVoice: true)
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

            homeVoice.onFamilyDoctorAppointment = {
                DispatchQueue.main.async {
                    shouldStartHomeVoice = false
                    homeVoice.stopAll()
                    showAileHekimiSheet = true
                }
            }

            homeVoice.onProfile = {
                DispatchQueue.main.async {
                    shouldStartHomeVoice = false
                    homeVoice.stopAll()
                    pushProfile = true
                }
            }
            homeVoice.onLogout = {
                DispatchQueue.main.async {
                    shouldStartHomeVoice = false
                    homeVoice.stopAll()
                    dismiss()
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
        errorMessage = nil

        defer { isLoading = false }

        let url = APIConfig.appointmentsByUserURL(userId: userId)

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "Sunucudan geçersiz cevap geldi."
                return
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                let serverMessage = String(data: data, encoding: .utf8) ?? ""
                print("Sunucu hatası:", httpResponse.statusCode, serverMessage)
                errorMessage = "Randevular alınamadı."
                return
            }

            let decoder = JSONDecoder()
            let decoded = try decoder.decode([AppointmentDTO].self, from: data)

            appointments = decoded.sorted {
                ($0.appointmentDateTime ?? "") < ($1.appointmentDateTime ?? "")
            }

            print("Randevular başarıyla çekildi:", appointments.count)

        } catch let error as DecodingError {
            print("Decode hatası:", error)
            errorMessage = "Randevu verisi okunamadı."
        } catch {
            print("Bağlantı hatası:", error.localizedDescription)
            errorMessage = "Sunucuya bağlanılamadı."
        }
    }
    @MainActor
    private func deleteAppointment(_ appointment: AppointmentDTO) async {
        let url = APIConfig.deleteAppointmentURL(appointmentId: appointment.id)

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                errorMessage = "Sunucudan geçersiz cevap geldi."
                return
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                let message = String(data: data, encoding: .utf8) ?? ""
                print("İptal hatası:", httpResponse.statusCode, message)
                errorMessage = "Randevu iptal edilemedi."
                return
            }

            appointments.removeAll { $0.id == appointment.id }

        } catch {
            print("Randevu iptal bağlantı hatası:", error.localizedDescription)
            errorMessage = "Bağlantı hatası oluştu."
        }
    }
    private func readAppointmentsWithVoice() {
        if appointments.isEmpty {
            homeVoice.speakAndAskAnotherRequest("Randevunuz bulunmamaktadır. Başka isteğiniz var mı?")
            return
        }

        var message = "\(userName), randevularınızı okuyorum. "

        for (index, appointment) in appointments.enumerated() {
            if index > 0 {
                message += "Diğer randevunuz. "
            }

            let clinicName = appointment.doctor?.clinic?.name
                ?? appointment.doctor?.specialization
                ?? "Bilinmeyen klinik"

            let doctorName = appointment.doctor?.name ?? "Doktor bilgisi yok"

            let dateText: String
            if let rawDate = appointment.appointmentDateTime {
                dateText = formatAppointmentDateForVoice(rawDate)
            } else {
                dateText = "Tarih bilgisi yok"
            }

            message += "\(clinicName), \(doctorName), \(dateText). "
        }

        message += "Başka isteğiniz var mı?"
        homeVoice.speakAndAskAnotherRequest(message)
    }

    private func formatAppointmentDateForVoice(_ rawDate: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.locale = Locale(identifier: "tr_TR")
        inputFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        let outputFormatter = DateFormatter()
        outputFormatter.locale = Locale(identifier: "tr_TR")
        outputFormatter.dateFormat = "dd MMMM yyyy HH:mm"

        if let date = inputFormatter.date(from: rawDate) {
            return outputFormatter.string(from: date)
        }

        return rawDate.replacingOccurrences(of: "T", with: " ")
    }
    private func restartHomeVoiceFlowAfterReturn() {
        shouldStartHomeVoice = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            if shouldStartHomeVoice {
                homeVoice.startInitialFlow()
            }
        }
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
struct AppointmentDTO: Identifiable, Codable {
    let id: Int
    let user: AppointmentUserDTO?
    let doctor: DoctorDTO?
    let appointmentDateTime: String?
    let status: String?
    let notes: String?
}

struct AppointmentUserDTO: Codable, Hashable {
    let id: Int?
    let name: String?
    let surname: String?
    let tcKimlik: String?
    let phone: String?
    let cinsiyet: String?
    let dogumTarihi: String?
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

// MARK: - Appointment Card
struct AppointmentCard: View {
    let appointment: AppointmentDTO
    let onCancel: () -> Void

    @State private var showCancelAlert = false

    private var isPastAppointment: Bool {
        guard let rawDate = appointment.appointmentDateTime else {
            return false
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        guard let appointmentDate = formatter.date(from: rawDate) else {
            return false
        }

        return appointmentDate < Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        appointment.doctor?.clinic?.name
                        ?? appointment.doctor?.specialization
                        ?? "Klinik bilgisi yok"
                    )
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

            if isPastAppointment {
                Text("Geçmiş randevunuz")
                    .font(.headline)
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            } else {
                Button(role: .destructive) {
                    showCancelAlert = true
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text("Randevuyu İptal Et")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(14)
        .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)
        .alert("Randevu iptal edilsin mi?", isPresented: $showCancelAlert) {
            Button("Vazgeç", role: .cancel) { }

            Button("İptal Et", role: .destructive) {
                onCancel()
            }
        } message: {
            Text("Bu işlem geri alınamaz.")
        }
    }

    private func formatDate(_ rawDate: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.locale = Locale(identifier: "tr_TR")
        inputFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        let outputFormatter = DateFormatter()
        outputFormatter.locale = Locale(identifier: "tr_TR")
        outputFormatter.dateFormat = "dd MMMM yyyy HH:mm"

        if let date = inputFormatter.date(from: rawDate) {
            return outputFormatter.string(from: date)
        }

        return rawDate.replacingOccurrences(of: "T", with: " ")
    }
}
