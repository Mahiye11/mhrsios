import SwiftUI
import CoreLocation
import Speech
import AVFoundation

// MARK: - DTO'lar

struct AppointmentClinicDTO: Identifiable, Decodable, Hashable {
    let id: Int
    let name: String
    let location: String?
}

struct AppointmentHospitalDTO: Identifiable, Decodable, Hashable {
    let id: Int
    let name: String
    let city: String?
    let district: String?
}

struct AppointmentDoctorDTO: Identifiable, Decodable, Hashable {
    let id: Int
    let name: String
    let specialization: String?
    let clinic: AppointmentClinicDTO?
}

// MARK: - Request DTO'lar

struct CreateAppointmentRequest: Encodable {
    let user: AppointmentIdDTO
    let doctor: AppointmentIdDTO
    let appointmentDateTime: String
    let notes: String?
}

struct AppointmentIdDTO: Encodable {
    let id: Int
}

// MARK: - UI Models

struct TimeSlotUI: Identifiable, Hashable {
    let id = UUID()
    let time: String
    let available: Bool
}

enum AppointmentVoiceStep {
    case chooseMode
    case city
    case district
    case clinic
    case hospital
    case doctor
    case finished
    case manual
}

// MARK: - Backend API

enum AppointmentAPI {

    static func cities() async throws -> [String] {
        let url = URL(string: "\(APIConfig.baseURL)/api/appointments/cities")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([String].self, from: data)
    }

    static func districts(city: String) async throws -> [String] {
        let encodedCity = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? city
        let url = URL(string: "\(APIConfig.baseURL)/api/appointments/districts?city=\(encodedCity)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([String].self, from: data)
    }

    static func clinics() async throws -> [AppointmentClinicDTO] {
        let url = URL(string: "\(APIConfig.baseURL)/api/appointments/clinics")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([AppointmentClinicDTO].self, from: data)
    }

    static func hospitals(clinicId: Int, city: String, district: String) async throws -> [AppointmentHospitalDTO] {
        let encodedCity = city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? city
        let encodedDistrict = district.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? district

        let url = URL(string: "\(APIConfig.baseURL)/api/appointments/hospitals?clinicId=\(clinicId)&city=\(encodedCity)&district=\(encodedDistrict)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([AppointmentHospitalDTO].self, from: data)
    }

    static func doctors(hospitalId: Int, clinicId: Int) async throws -> [AppointmentDoctorDTO] {
        let url = URL(string: "\(APIConfig.baseURL)/api/appointments/doctors-for-appointment?hospitalId=\(hospitalId)&clinicId=\(clinicId)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([AppointmentDoctorDTO].self, from: data)
    }

    static func availableSlots(doctorId: Int, date: String) async throws -> [String] {
        let url = APIConfig.availableSlotsURL(doctorId: doctorId, date: date)
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([String].self, from: data)
    }
}

// MARK: - View

struct HastaneRandevuView: View {
    let userId: Int
    let initialClinic: String?

    @Environment(\.dismiss) private var dismiss

    @StateObject private var locationManager = AppointmentLocationManager()
    @StateObject private var voiceManager = AppointmentVoiceManager()

    @State private var voiceStep: AppointmentVoiceStep = .chooseMode

    @State private var iller: [String] = []
    @State private var ilceler: [String] = []
    @State private var klinikler: [AppointmentClinicDTO] = []
    @State private var hastaneler: [AppointmentHospitalDTO] = []
    @State private var doktorlar: [AppointmentDoctorDTO] = []

    @State private var secilenIl: String?
    @State private var secilenIlce: String?
    @State private var secilenKlinik: AppointmentClinicDTO?
    @State private var secilenHastane: AppointmentHospitalDTO?
    @State private var secilenDoktor: AppointmentDoctorDTO?

    @State private var availableTimes: [String] = []

    @State private var showCalendar = false
    @State private var selectedDate: String?
    @State private var selectedTime: String?

    @State private var alertMessage: String?

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    headerView
                    appointmentInfoCard

                    if showCalendar {
                        dateTimeSection
                    }

                    actionButtons
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Randevu Ara")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    voiceManager.stopAll()
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Geri")
                    }
                }
            }
        }
        .task {
            locationManager.requestLocationPermissionOnce()
            await ilkVerileriYukle()

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                voiceStep = .chooseMode
                voiceManager.speakAndListen("Sesli komutla devam etmek ister misiniz, yoksa manuel mi?")
            }
        }
        .onReceive(voiceManager.$recognizedText) { text in
            guard !text.isEmpty else { return }
            guard !voiceManager.isSpeaking else { return }
            guard voiceManager.isListening == false else { return }

            Task {
                await handleVoiceCommand(text)
            }
        }
        .onChange(of: locationManager.detectedCity) { _, city in
            guard let city else { return }

            if let matchedCity = iller.first(where: {
                normalizeVoiceText($0).contains(normalizeVoiceText(city)) ||
                normalizeVoiceText(city).contains(normalizeVoiceText($0))
            }) {
                secilenIl = matchedCity
            }
        }
        .onChange(of: locationManager.detectedDistrict) { _, district in
            guard let district else { return }

            if let matchedDistrict = ilceler.first(where: {
                normalizeVoiceText($0).contains(normalizeVoiceText(district)) ||
                normalizeVoiceText(district).contains(normalizeVoiceText($0))
            }) {
                secilenIlce = matchedDistrict
            }
        }
        .onDisappear {
            voiceManager.stopAll()
        }
        .alert("Uyarı", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("Tamam") {
                let message = alertMessage
                alertMessage = nil

                if message == "Randevunuz başarıyla oluşturuldu." {
                    dismiss()
                }
            }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(secilenDoktor?.name ?? "Doktor Seçimi")
                .font(.title3.bold())

            Text("Uygun tarih ve saat seçimi")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white)
        .cornerRadius(22)
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
    }

    private var appointmentInfoCard: some View {
        VStack(spacing: 0) {

            pickerRow(title: "İl") {
                Picker("İl", selection: $secilenIl) {
                    Text("Seçiniz").tag(nil as String?)
                    ForEach(iller, id: \.self) { il in
                        Text(il).tag(Optional(il))
                    }
                }
                .pickerStyle(.menu)
            }
            .onChange(of: secilenIl) { _, yeniIl in
                Task {
                    secilenIlce = nil
                    ilceler = []
                    secilenHastane = nil
                    hastaneler = []
                    secilenDoktor = nil
                    doktorlar = []
                    availableTimes = []
                    resetDateSelection()

                    guard let yeniIl else { return }

                    do {
                        ilceler = try await AppointmentAPI.districts(city: yeniIl)

                        if let detectedDistrict = locationManager.detectedDistrict {
                            secilenIlce = ilceler.first(where: {
                                normalizeVoiceText($0).contains(normalizeVoiceText(detectedDistrict)) ||
                                normalizeVoiceText(detectedDistrict).contains(normalizeVoiceText($0))
                            })
                        }
                    } catch {
                        alertMessage = "İlçeler yüklenemedi."
                    }
                }
            }

            divider

            pickerRow(title: "İlçe") {
                Picker("İlçe", selection: $secilenIlce) {
                    Text("Seçiniz").tag(nil as String?)
                    ForEach(ilceler, id: \.self) { ilce in
                        Text(ilce).tag(Optional(ilce))
                    }
                }
                .pickerStyle(.menu)
            }
            .onChange(of: secilenIlce) { _, _ in
                Task {
                    secilenHastane = nil
                    hastaneler = []
                    secilenDoktor = nil
                    doktorlar = []
                    availableTimes = []
                    resetDateSelection()
                    await hastaneleriYukle()
                }
            }

            divider

            pickerRow(title: "Hastane") {
                Picker("Hastane", selection: $secilenHastane) {
                    Text("Seçiniz").tag(nil as AppointmentHospitalDTO?)
                    ForEach(hastaneler) { hastane in
                        Text(hastane.name).tag(Optional(hastane))
                    }
                }
                .pickerStyle(.menu)
            }
            .onChange(of: secilenHastane) { _, _ in
                Task {
                    secilenDoktor = nil
                    doktorlar = []
                    availableTimes = []
                    resetDateSelection()
                    await doktorlariYukle()
                }
            }

            divider

            pickerRow(title: "Klinik") {
                Picker("Klinik", selection: $secilenKlinik) {
                    Text("Seçiniz").tag(nil as AppointmentClinicDTO?)
                    ForEach(klinikler) { klinik in
                        Text(klinik.name).tag(Optional(klinik))
                    }
                }
                .pickerStyle(.menu)
            }
            .onChange(of: secilenKlinik) { _, _ in
                Task {
                    secilenHastane = nil
                    hastaneler = []
                    secilenDoktor = nil
                    doktorlar = []
                    availableTimes = []
                    resetDateSelection()
                    await hastaneleriYukle()
                }
            }

            divider

            pickerRow(title: "Doktor") {
                Picker("Doktor", selection: $secilenDoktor) {
                    Text("Seçiniz").tag(nil as AppointmentDoctorDTO?)
                    ForEach(doktorlar) { doktor in
                        Text(doktor.name).tag(Optional(doktor))
                    }
                }
                .pickerStyle(.menu)
            }
            .onChange(of: secilenDoktor) { _, _ in
                availableTimes = []
                resetDateSelection()
            }
        }
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
    }

    private var dateTimeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tarih Seçiniz")
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            CalendarGridView(
                onDateSelected: { date in
                    Task {
                        await loadAvailableSlots(date: date)
                    }
                },
                selectedDate: $selectedDate,
                selectedTime: $selectedTime
            )

            if selectedDate != nil {
                Text("Saat Seçiniz")
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.top, 6)

                TimeSlotGrid(
                    slots: buildTimeSlotsWithAvailability(availableTimes: availableTimes),
                    selectedDate: selectedDate,
                    selectedTime: selectedTime,
                    currentDate: selectedDate ?? "",
                    onSlotSelected: { time in
                        selectedTime = time
                    }
                )
                .padding()
                .background(Color.white)
                .cornerRadius(20)
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button {
                voiceManager.stopAll()
                voiceStep = .manual
                randevuAra()
            } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text(showCalendar ? "Bilgileri Güncelle" : "Randevu Ara")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(16)
            }

            Button {
                voiceManager.stopAll()
                randevuyuOnayla()
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Randevuyu Onayla")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    selectedDate != nil && selectedTime != nil
                    ? Color.red
                    : Color.gray.opacity(0.35)
                )
                .foregroundColor(.white)
                .cornerRadius(16)
            }
            .disabled(selectedDate == nil || selectedTime == nil)

            Button(role: .destructive) {
                voiceManager.stopAll()
                temizle()
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Temizle")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
            }
            .background(Color.white)
            .cornerRadius(16)
        }
        .padding(.top, 4)
    }

    private func pickerRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(title)
                .font(.title3)

            Spacer()

            content()
                .tint(.gray)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.gray.opacity(0.22))
            .frame(height: 1)
            .padding(.leading, 18)
    }

    @MainActor
    private func ilkVerileriYukle() async {
        do {
            async let citiesTask = AppointmentAPI.cities()
            async let clinicsTask = AppointmentAPI.clinics()

            iller = try await citiesTask
            klinikler = try await clinicsTask

            if let initialClinic, !initialClinic.isEmpty {
                secilenKlinik = klinikler.first {
                    normalizeVoiceText($0.name).contains(normalizeVoiceText(initialClinic)) ||
                    normalizeVoiceText(initialClinic).contains(normalizeVoiceText($0.name))
                }
            }

        } catch {
            print("İlk veri yükleme hatası:", error.localizedDescription)
            alertMessage = "İl ve klinikler yüklenemedi."
        }
    }

    @MainActor
    private func hastaneleriYukle() async {
        guard let il = secilenIl,
              let ilce = secilenIlce,
              let klinik = secilenKlinik else {
            return
        }

        do {
            hastaneler = try await AppointmentAPI.hospitals(
                clinicId: klinik.id,
                city: il,
                district: ilce
            )
        } catch {
            print("Hastane yükleme hatası:", error.localizedDescription)
            alertMessage = "Hastaneler yüklenemedi."
        }
    }

    @MainActor
    private func doktorlariYukle() async {
        guard let hastane = secilenHastane,
              let klinik = secilenKlinik else {
            return
        }

        do {
            doktorlar = try await AppointmentAPI.doctors(
                hospitalId: hastane.id,
                clinicId: klinik.id
            )
        } catch {
            print("Doktor yükleme hatası:", error.localizedDescription)
            alertMessage = "Doktorlar yüklenemedi."
        }
    }

    @MainActor
    private func loadAvailableSlots(date: String) async {
        guard let doctorId = secilenDoktor?.id else {
            alertMessage = "Lütfen önce doktor seçiniz."
            return
        }

        do {
            availableTimes = try await AppointmentAPI.availableSlots(
                doctorId: doctorId,
                date: date
            )
        } catch {
            print("Saat yükleme hatası:", error.localizedDescription)
            alertMessage = "Uygun saatler yüklenemedi."
        }
    }

    @MainActor
    private func createAppointment(doctorId: Int, date: String, time: String) async {
        let appointmentDateTime = "\(date)T\(time):00"

        let body = CreateAppointmentRequest(
            user: AppointmentIdDTO(id: userId),
            doctor: AppointmentIdDTO(id: doctorId),
            appointmentDateTime: appointmentDateTime,
            notes: nil
        )

        do {
            var request = URLRequest(url: APIConfig.createAppointmentURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                alertMessage = "Sunucudan geçersiz cevap geldi."
                return
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                let serverMessage = String(data: data, encoding: .utf8) ?? ""
                print("Randevu oluşturma hatası:", httpResponse.statusCode, serverMessage)
                alertMessage = serverMessage.isEmpty ? "Randevu oluşturulamadı." : serverMessage
                return
            }

            alertMessage = "Randevunuz başarıyla oluşturuldu."
            temizle()

        } catch {
            print("Randevu oluşturma bağlantı hatası:", error.localizedDescription)
            alertMessage = "Bağlantı hatası oluştu."
        }
    }

    @MainActor
    private func handleVoiceCommand(_ rawText: String) async {
        let text = normalizeVoiceText(rawText)
        voiceManager.clearRecognizedText()

        switch voiceStep {

        case .chooseMode:
            if text.contains("manuel") || text.contains("elle") {
                voiceStep = .manual
                voiceManager.speakOnly("Manuel moda geçiyorum. Seçimlerinizi ekrandan yapabilirsiniz.")
                return
            }

            if text.contains("sesli") || text.contains("ses") || text.contains("sesle") {
                voiceStep = .city
                voiceManager.speakAndListen("Sesli moda geçiyorum. Lütfen il söyleyin.")
                return
            }

            voiceManager.speakAndListen("Anlayamadım. Sesli komut mu, manuel mi?")
            return

        case .city:
            if let matchedCity = iller.first(where: {
                normalizeVoiceText($0).contains(text) || text.contains(normalizeVoiceText($0))
            }) {
                secilenIl = matchedCity

                do {
                    ilceler = try await AppointmentAPI.districts(city: matchedCity)
                } catch {
                    voiceManager.speakAndListen("İlçeler yüklenemedi. Lütfen tekrar il söyleyin.")
                    return
                }

                voiceStep = .district
                voiceManager.speakAndListen("\(matchedCity) seçildi. Lütfen ilçe söyleyin.")
            } else {
                voiceManager.speakAndListen("Bu ili bulamadım. Lütfen tekrar il söyleyin.")
            }

        case .district:
            if let matchedDistrict = ilceler.first(where: {
                normalizeVoiceText($0).contains(text) || text.contains(normalizeVoiceText($0))
            }) {
                secilenIlce = matchedDistrict
                voiceStep = .clinic
                voiceManager.speakAndListen("\(matchedDistrict) seçildi. Lütfen klinik söyleyin.")
            } else {
                voiceManager.speakAndListen("Bu ilçeyi bulamadım. Lütfen tekrar ilçe söyleyin.")
            }
        case .clinic:
            if let matchedClinic = klinikler.first(where: {
                normalizeVoiceText($0.name).contains(text) || text.contains(normalizeVoiceText($0.name))
            }) {
                secilenKlinik = matchedClinic

                await hastaneleriYukle()

                voiceStep = .hospital
                voiceManager.speakAndListen("\(matchedClinic.name) seçildi. Lütfen hastane söyleyin.")
            } else {
                voiceManager.speakAndListen("Bu kliniği bulamadım. Lütfen tekrar klinik söyleyin.")
            }

        case .hospital:
            if let matchedHospital = hastaneler.first(where: {
                normalizeVoiceText($0.name).contains(text) || text.contains(normalizeVoiceText($0.name))
            }) {
                secilenHastane = matchedHospital
                await doktorlariYukle()

                voiceStep = .doctor
                voiceManager.speakAndListen("\(matchedHospital.name) seçildi. Lütfen doktor adı söyleyin.")
            } else {
                voiceManager.speakAndListen("Bu hastaneyi bulamadım. Lütfen tekrar hastane söyleyin.")
            }

        case .doctor:
            if let matchedDoctor = doktorlar.first(where: {
                normalizeVoiceText($0.name).contains(text) || text.contains(normalizeVoiceText($0.name))
            }) {
                secilenDoktor = matchedDoctor
                voiceStep = .finished

                withAnimation {
                    showCalendar = true
                    selectedDate = nil
                    selectedTime = nil
                }

                voiceManager.speakOnly("\(matchedDoctor.name) seçildi. Şimdi ekrandan tarih ve saat seçebilirsiniz.")
            } else {
                voiceManager.speakAndListen("Bu doktoru bulamadım. Lütfen tekrar doktor adı söyleyin.")
            }

        case .finished, .manual:
            return
        }
    }

    private func randevuAra() {
        guard secilenIl != nil,
              secilenIlce != nil,
              secilenHastane != nil,
              secilenKlinik != nil,
              secilenDoktor != nil else {
            alertMessage = "Lütfen il, ilçe, hastane, klinik ve doktor seçiniz."
            return
        }

        withAnimation {
            showCalendar = true
            selectedDate = nil
            selectedTime = nil
        }
    }

    private func randevuyuOnayla() {
        guard let secilenDoktor else {
            alertMessage = "Lütfen doktor seçiniz."
            return
        }

        guard let selectedDate,
              let selectedTime else {
            alertMessage = "Lütfen tarih ve saat seçiniz."
            return
        }

        Task {
            await createAppointment(
                doctorId: secilenDoktor.id,
                date: selectedDate,
                time: selectedTime
            )
        }
    }

    private func resetDateSelection() {
        showCalendar = false
        selectedDate = nil
        selectedTime = nil
    }

    private func temizle() {
        secilenIl = nil
        secilenIlce = nil
        ilceler = []
        secilenKlinik = nil
        secilenHastane = nil
        hastaneler = []
        secilenDoktor = nil
        doktorlar = []
        availableTimes = []
        voiceStep = .chooseMode
        resetDateSelection()
    }

    private func normalizeVoiceText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "ğ", with: "g")
            .replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: "ş", with: "s")
            .replacingOccurrences(of: "ö", with: "o")
            .replacingOccurrences(of: "ç", with: "c")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Calendar

struct CalendarGridView: View {
    let onDateSelected: (String) -> Void
    @Binding var selectedDate: String?
    @Binding var selectedTime: String?

    private let columns = Array(repeating: GridItem(.flexible()), count: 7)

    private var availableDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (0..<14).compactMap {
            calendar.date(byAdding: .day, value: $0, to: today)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Text(monthTitle)
                .font(.title3.bold())

            HStack {
                ForEach(["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"], id: \.self) { day in
                    Text(day)
                        .font(.caption.bold())
                        .foregroundColor(.gray)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(leadingEmptyDays, id: \.self) { _ in
                    Color.clear
                        .frame(height: 42)
                }

                ForEach(availableDays, id: \.self) { date in
                    let backend = backendDate(date)
                    let isSelected = selectedDate == backend

                    Button {
                        selectedDate = backend
                        selectedTime = nil
                        onDateSelected(backend)
                    } label: {
                        Text("\(Calendar.current.component(.day, from: date))")
                            .font(.headline)
                            .frame(width: 42, height: 42)
                            .background(isSelected ? Color.red : Color.white)
                            .foregroundColor(isSelected ? .white : .primary)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(isSelected ? Color.red : Color.blue.opacity(0.35), lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
    }

    private var leadingEmptyDays: [Int] {
        guard let first = availableDays.first else { return [] }

        let weekday = Calendar.current.component(.weekday, from: first)
        let mondayBased = (weekday + 5) % 7

        return Array(0..<mondayBased)
    }

    private var monthTitle: String {
        guard let first = availableDays.first else { return "" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "MMMM yyyy"

        return formatter.string(from: first).capitalized
    }

    private func backendDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

// MARK: - Time Grid

struct TimeSlotGrid: View {
    let slots: [TimeSlotUI]
    let selectedDate: String?
    let selectedTime: String?
    let currentDate: String
    let onSlotSelected: (String) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(slots) { slot in
                let selected = selectedDate == currentDate && selectedTime == slot.time

                Button {
                    if slot.available {
                        onSlotSelected(slot.time)
                    }
                } label: {
                    HStack(spacing: 5) {
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                        }

                        if !slot.available {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                        }

                        Text(slot.time)
                            .font(.subheadline.bold())
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(
                        selected
                        ? Color.red
                        : slot.available
                            ? Color.white
                            : Color.gray.opacity(0.18)
                    )
                    .foregroundColor(
                        selected
                        ? .white
                        : slot.available
                            ? .blue
                            : .gray
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                selected
                                ? Color.red
                                : slot.available
                                    ? Color.blue
                                    : Color.gray.opacity(0.35),
                                lineWidth: slot.available ? 2 : 1
                            )
                    )
                    .cornerRadius(14)
                }
                .disabled(!slot.available)
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Helpers

func buildTimeSlotsWithAvailability(availableTimes: [String]) -> [TimeSlotUI] {
    var allTimes: [String] = []

    var hour = 9
    var minute = 0

    while hour < 17 {
        let time = String(format: "%02d:%02d", hour, minute)
        let isLunchBreak = time >= "12:00" && time < "13:00"

        if !isLunchBreak {
            allTimes.append(time)
        }

        minute += 10

        if minute >= 60 {
            minute = 0
            hour += 1
        }
    }

    return allTimes.map { time in
        TimeSlotUI(
            time: time,
            available: availableTimes.contains(time)
        )
    }
}

// MARK: - Location Manager

final class AppointmentLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    @Published var detectedCity: String?
    @Published var detectedDistrict: String?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestLocationPermissionOnce() {
        let status = manager.authorizationStatus
        print("Konum izin durumu:", status.rawValue)

        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
            return
        }

        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
            return
        }

        if status == .denied || status == .restricted {
            print("Konum izni reddedilmiş. Ayarlardan açılmalı.")
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus

        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            if let error {
                print("Konum şehir çevirme hatası:", error.localizedDescription)
                return
            }

            guard let placemark = placemarks?.first else { return }

            DispatchQueue.main.async {
                self?.detectedCity = placemark.administrativeArea
                self?.detectedDistrict = placemark.subAdministrativeArea ?? placemark.locality
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Konum alınamadı:", error.localizedDescription)
    }
}

// MARK: - Voice Manager

@MainActor
final class AppointmentVoiceManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    @Published var recognizedText: String = ""
    @Published var isListening = false
    @Published var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
    private let audioEngine = AVAudioEngine()

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?

    private var lastText = ""
    private var shouldListenAfterSpeaking = false

    override init() {
        super.init()
        synthesizer.delegate = self
        requestPermissions()
    }

    func clearRecognizedText() {
        recognizedText = ""
    }

    func speakOnly(_ text: String) {
        speak(text, listenAfter: false)
    }

    func speakAndListen(_ text: String) {
        speak(text, listenAfter: true)
    }

    func stopAll() {
        silenceTask?.cancel()
        silenceTask = nil
        stopListening()
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        shouldListenAfterSpeaking = false
    }

    private func speak(_ text: String, listenAfter: Bool) {
        stopListening()

        recognizedText = ""
        lastText = ""
        silenceTask?.cancel()
        silenceTask = nil

        shouldListenAfterSpeaking = listenAfter
        isSpeaking = true

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("TTS session hata:", error.localizedDescription)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "tr-TR")
        utterance.rate = 0.45
        utterance.volume = 1.0

        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.isSpeaking = false

            guard self.shouldListenAfterSpeaking else { return }

            self.shouldListenAfterSpeaking = false

            try? await Task.sleep(nanoseconds: 700_000_000)
            self.startListening()
        }
    }

    private func startListening() {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            print("Speech izni yok.")
            return
        }
        recognizedText = ""
        lastText = ""

        stopListening()

        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .duckOthers, .allowBluetooth]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Mikrofon session hata:", error.localizedDescription)
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest else { return }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        let format = inputNode.inputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            print("Geçersiz mikrofon formatı")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
            isListening = true
        } catch {
            print("Audio engine hata:", error.localizedDescription)
            isListening = false
            return
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            Task { @MainActor in
                if let result {
                    let text = result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    if !text.isEmpty {
                        self.lastText = text
                        self.restartSilenceTimer()
                    }
                }

                if let error {
                    print("Speech hata:", error.localizedDescription)
                }
            }
        }

        restartSilenceTimer()
    }

    private func restartSilenceTimer() {
        silenceTask?.cancel()

        silenceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)

            await MainActor.run {
                self?.finishListening()
            }
        }
    }

    private func finishListening() {
        let finalText = lastText.trimmingCharacters(in: .whitespacesAndNewlines)

        stopListening()

        guard !finalText.isEmpty else {
            speakAndListen("Sesinizi alamadım. Lütfen tekrar söyleyin.")
            return
        }
        recognizedText = finalText

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.recognizedText = ""
        }
    }

    private func stopListening() {
        silenceTask?.cancel()
        silenceTask = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }

        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        isListening = false
    }

    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            print("Speech izin durumu:", status.rawValue)
        }

        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            print("Mikrofon izni:", granted)
        }
    }
}

#Preview {
    NavigationStack {
        HastaneRandevuView(userId: 1, initialClinic: nil)
    }
}
