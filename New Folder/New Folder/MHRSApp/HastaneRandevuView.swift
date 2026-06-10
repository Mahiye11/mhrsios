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
    case date
    case time
    case creatingAppointment
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

    static func userAppointments(userId: Int) async throws -> [AppointmentDTO] {
        let url = APIConfig.appointmentsByUserURL(userId: userId)
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([AppointmentDTO].self, from: data)
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
    @State private var isVoiceFlowActive = false
    @State private var isProcessingVoiceAnswer = false

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
                    isVoiceFlowActive = false
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

            let hasVoicePermission = await voiceManager.requestPermissionsIfNeeded()

            guard hasVoicePermission else {
                alertMessage = "Sesli komut için mikrofon ve konuşma tanıma izinleri gerekli."
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                voiceStep = .chooseMode
                voiceManager.speakAndListen("Sesli komutla devam etmek ister misiniz, yoksa manuel mi?")
            }
        }
        .onReceive(voiceManager.$recognizedText) { text in
            let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanText.isEmpty, !isProcessingVoiceAnswer else { return }

            Task {
                await handleVoiceCommand(cleanText)
            }
        }
        .onReceive(voiceManager.$emptySpeechCount) { count in
            guard count > 0,
                  !isProcessingVoiceAnswer,
                  !voiceManager.isSpeaking else {
                return
            }

            Task {
                await repeatCurrentVoiceQuestionAfterNoSpeech()
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
            isVoiceFlowActive = false
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
                guard !isVoiceFlowActive else { return }

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
                guard !isVoiceFlowActive else { return }

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
                guard !isVoiceFlowActive else { return }

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
                guard !isVoiceFlowActive else { return }

                Task {
                    secilenDoktor = nil
                    doktorlar = []
                    availableTimes = []
                    resetDateSelection()
                    await doktorlariYukle()
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
                guard !isVoiceFlowActive else { return }

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
                isVoiceFlowActive = false
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
                isVoiceFlowActive = false
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
                isVoiceFlowActive = false
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
    private func createAppointment(doctorId: Int, date: String, time: String) async -> Bool {
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
                return false
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                let serverMessage = String(data: data, encoding: .utf8) ?? ""
                print("Randevu oluşturma hatası:", httpResponse.statusCode, serverMessage)
                alertMessage = serverMessage.isEmpty ? "Randevu oluşturulamadı." : serverMessage
                return false
            }

            alertMessage = "Randevunuz başarıyla oluşturuldu."
            return true

        } catch {
            print("Randevu oluşturma bağlantı hatası:", error.localizedDescription)
            alertMessage = "Bağlantı hatası oluştu."
            return false
        }
    }

    @MainActor
    private func handleVoiceCommand(_ rawText: String) async {
        guard !isProcessingVoiceAnswer else { return }

        isProcessingVoiceAnswer = true
        defer { isProcessingVoiceAnswer = false }

        let text = normalizeVoiceText(rawText)
        voiceManager.clearRecognizedText()

        switch voiceStep {

        case .chooseMode:
            if text.contains("manuel") || text.contains("elle") || text.contains("hayır") || text.contains("hayir") {
                isVoiceFlowActive = false
                voiceStep = .manual
                voiceManager.speakOnly("Manuel moda geçiyorum. Seçimlerinizi ekrandan yapabilirsiniz.")
                return
            }

            if text.contains("evet") || text.contains("sesli") || text.contains("ses") || text.contains("sesle") {
                isVoiceFlowActive = true
                voiceStep = .city
                voiceManager.speakAndListen("Sesli moda geçiyorum. Lütfen il söyleyin.")
                return
            }

            voiceManager.speakAndListen("Anlayamadım. Sesli devam etmek istiyorsanız evet, manuel devam etmek istiyorsanız manuel deyin.")

        case .city:
            guard isVoiceFlowActive else { return }

            guard let matchedCity = iller.first(where: {
                normalizeVoiceText($0).contains(text) || text.contains(normalizeVoiceText($0))
            }) else {
                voiceManager.speakAndListen("Bu ili bulamadım. Lütfen tekrar il söyleyin.")
                return
            }

            secilenIl = matchedCity
            secilenIlce = nil
            ilceler = []
            secilenHastane = nil
            hastaneler = []
            secilenDoktor = nil
            doktorlar = []
            availableTimes = []
            resetDateSelection()

            do {
                ilceler = try await AppointmentAPI.districts(city: matchedCity)
            } catch {
                voiceManager.speakAndListen("İlçeler yüklenemedi. Lütfen tekrar il söyleyin.")
                return
            }

            voiceStep = .district
            voiceManager.speakAndListen("\(matchedCity) seçildi. Lütfen ilçe söyleyin.")

        case .district:
            guard isVoiceFlowActive else { return }

            guard let matchedDistrict = ilceler.first(where: {
                normalizeVoiceText($0).contains(text) || text.contains(normalizeVoiceText($0))
            }) else {
                voiceManager.speakAndListen("Bu ilçeyi bulamadım. Lütfen tekrar ilçe söyleyin.")
                return
            }

            secilenIlce = matchedDistrict
            secilenHastane = nil
            hastaneler = []
            secilenDoktor = nil
            doktorlar = []
            availableTimes = []
            resetDateSelection()

            voiceStep = .clinic
            voiceManager.speakAndListen("\(matchedDistrict) seçildi. Lütfen klinik söyleyin.")

        case .clinic:
            guard isVoiceFlowActive else { return }

            guard let matchedClinic = klinikler.first(where: {
                normalizeVoiceText($0.name).contains(text) || text.contains(normalizeVoiceText($0.name))
            }) else {
                voiceManager.speakAndListen("Bu kliniği bulamadım. Lütfen tekrar klinik söyleyin.")
                return
            }

            secilenKlinik = matchedClinic
            secilenHastane = nil
            hastaneler = []
            secilenDoktor = nil
            doktorlar = []
            availableTimes = []
            resetDateSelection()

            await hastaneleriYukle()

            guard !hastaneler.isEmpty else {
                voiceManager.speakAndListen("Bu il, ilçe ve klinik için hastane bulunamadı. Lütfen tekrar klinik söyleyin.")
                return
            }

            voiceStep = .hospital
            voiceManager.speakAndListen("\(matchedClinic.name) seçildi. Lütfen hastane söyleyin.")

        case .hospital:
            guard isVoiceFlowActive else { return }

            guard let matchedHospital = hastaneler.first(where: {
                normalizeVoiceText($0.name).contains(text) || text.contains(normalizeVoiceText($0.name))
            }) else {
                voiceManager.speakAndListen("Bu hastaneyi bulamadım. Lütfen tekrar hastane söyleyin.")
                return
            }

            secilenHastane = matchedHospital
            secilenDoktor = nil
            doktorlar = []
            availableTimes = []
            resetDateSelection()

            await doktorlariYukle()

            guard !doktorlar.isEmpty else {
                voiceManager.speakAndListen("Bu hastane ve klinik için doktor bulunamadı. Lütfen tekrar hastane söyleyin.")
                return
            }

            voiceStep = .doctor
            voiceManager.speakAndListen("\(matchedHospital.name) seçildi. Lütfen doktor adı söyleyin.")

        case .doctor:
            guard isVoiceFlowActive else { return }

            guard let matchedDoctor = doktorlar.first(where: {
                normalizeVoiceText($0.name).contains(text) || text.contains(normalizeVoiceText($0.name))
            }) else {
                voiceManager.speakAndListen("Bu doktoru bulamadım. Lütfen tekrar doktor adı söyleyin.")
                return
            }

            secilenDoktor = matchedDoctor
            availableTimes = []

            withAnimation {
                showCalendar = true
                selectedDate = nil
                selectedTime = nil
            }

            voiceStep = .date
            voiceManager.speakAndListen("\(matchedDoctor.name) seçildi. Lütfen tarih söyleyin. Örneğin 15 Haziran.")

        case .date:
            guard isVoiceFlowActive else { return }

            guard let parsedDate = parseTurkishDate(text) else {
                voiceManager.speakAndListen("Tarihi anlayamadım. Lütfen tekrar söyleyin. Örneğin 15 Haziran.")
                return
            }

            guard isSelectableAppointmentDate(parsedDate) else {
                voiceManager.speakAndListen("Bu tarih takvimde seçilebilir değil. Lütfen önümüzdeki iki hafta içinden hafta içi bir tarih söyleyin.")
                return
            }

            selectedDate = parsedDate
            selectedTime = nil
            availableTimes = []

            await loadAvailableSlots(date: parsedDate)

            guard !availableTimes.isEmpty else {
                voiceManager.speakAndListen("Bu tarihte uygun saat bulunamadı. Lütfen başka bir tarih söyleyin.")
                return
            }

            voiceStep = .time

            let uygunSaatler = availableTimes.prefix(5).joined(separator: ", ")
            voiceManager.speakAndListen("Tarih seçildi. Uygun saatlerden bazıları: \(uygunSaatler). Lütfen saat söyleyin.")

        case .time:
            guard isVoiceFlowActive else { return }

            guard let formattedTime = parseTurkishTime(text) else {
                voiceManager.speakAndListen("Saati anlayamadım. Lütfen tekrar söyleyin. Örneğin 09 30.")
                return
            }

            guard availableTimes.contains(formattedTime) else {
                let uygunSaatler = availableTimes.prefix(5).joined(separator: ", ")
                voiceManager.speakAndListen("Bu saat uygun değil. Uygun saatlerden bazıları: \(uygunSaatler). Lütfen başka saat söyleyin.")
                return
            }

            selectedTime = formattedTime
            voiceStep = .creatingAppointment
            voiceManager.speakOnly("Randevunuz oluşturuluyor.")

            guard let doctorId = secilenDoktor?.id,
                  let selectedDate,
                  let selectedTime else {
                voiceStep = .time
                voiceManager.speakAndListen("Randevu bilgileri eksik. Lütfen tekrar saat söyleyin.")
                return
            }

            let success = await createAppointment(
                doctorId: doctorId,
                date: selectedDate,
                time: selectedTime
            )

            if success {
                alertMessage = nil
                isVoiceFlowActive = false
                voiceStep = .finished
                voiceManager.speakOnly("Randevunuz başarıyla oluşturuldu. Ana sayfaya yönlendiriliyorsunuz.")

                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    temizle()
                    dismiss()
                }
            } else {
                voiceStep = .time
                voiceManager.speakAndListen("Randevu oluşturulamadı. Lütfen başka bir saat söyleyin.")
            }

        case .creatingAppointment:
            return

        case .finished, .manual:
            return
        }
    }

    @MainActor
    private func repeatCurrentVoiceQuestionAfterNoSpeech() async {
        guard !voiceManager.isSpeaking,
              !isProcessingVoiceAnswer,
              voiceStep != .manual,
              voiceStep != .finished,
              voiceStep != .creatingAppointment else {
            return
        }

        let prompt: String

        switch voiceStep {
        case .chooseMode:
            prompt = "Sesli devam etmek istiyorsanız evet, manuel devam etmek istiyorsanız manuel deyin."
        case .city:
            prompt = "Sizi duyamadım. Lütfen il söyleyin."
        case .district:
            prompt = "Sizi duyamadım. Lütfen ilçe söyleyin."
        case .clinic:
            prompt = "Sizi duyamadım. Lütfen klinik söyleyin."
        case .hospital:
            prompt = "Sizi duyamadım. Lütfen hastane söyleyin."
        case .doctor:
            prompt = "Sizi duyamadım. Lütfen doktor adı söyleyin."
        case .date:
            prompt = "Sizi duyamadım. Lütfen tarih söyleyin. Örneğin 15 Haziran."
        case .time:
            prompt = "Sizi duyamadım. Lütfen saat söyleyin. Örneğin 09 30."
        case .creatingAppointment, .finished, .manual:
            return
        }

        voiceManager.speakAndListen(prompt)
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

        guard let secilenKlinik else {
            alertMessage = "Lütfen klinik seçiniz."
            return
        }

        guard let selectedDate,
              let selectedTime else {
            alertMessage = "Lütfen tarih ve saat seçiniz."
            return
        }

        Task {
            do {
                let mevcutRandevular = try await AppointmentAPI.userAppointments(userId: userId)

                let aktifAyniDoktorKlinikVar = mevcutRandevular.contains { randevu in
                    let status = randevu.status?.uppercased() ?? ""

                    let iptalDegil =
                        status != "CANCELLED" &&
                        status != "CANCELED" &&
                        status != "İPTAL" &&
                        status != "IPTAL"

                    return randevu.doctor?.id == secilenDoktor.id &&
                           randevu.doctor?.clinic?.id == secilenKlinik.id &&
                           iptalDegil
                }

                if aktifAyniDoktorKlinikVar {
                    alertMessage = "Bu doktor ve klinik için zaten aktif bir randevunuz var. İptal ettikten sonra tekrar randevu alabilirsiniz."
                    return
                }

                let success = await createAppointment(
                    doctorId: secilenDoktor.id,
                    date: selectedDate,
                    time: selectedTime
                )

                if success {
                    temizle()
                }

            } catch {
                print("Randevu kontrol hatası:", error.localizedDescription)
                alertMessage = "Mevcut randevular kontrol edilemedi."
            }
        }
    }

    private func resetDateSelection() {
        showCalendar = false
        selectedDate = nil
        selectedTime = nil
    }

    private func temizle() {
        isVoiceFlowActive = false
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
            .lowercased(with: Locale(identifier: "tr_TR"))
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

    private func parseTurkishDate(_ text: String) -> String? {
        let normalized = normalizeVoiceText(text)

        let monthMap: [String: Int] = [
            "ocak": 1,
            "subat": 2,
            "mart": 3,
            "nisan": 4,
            "mayis": 5,
            "haziran": 6,
            "temmuz": 7,
            "agustos": 8,
            "eylul": 9,
            "ekim": 10,
            "kasim": 11,
            "aralik": 12
        ]

        var selectedMonth: Int?

        for (monthName, monthNumber) in monthMap {
            if normalized.contains(monthName) {
                selectedMonth = monthNumber
                break
            }
        }

        let numbers = extractNumbers(from: normalized)

        guard let day = numbers.first else {
            return nil
        }

        let month: Int?

        if let selectedMonth {
            month = selectedMonth
        } else if numbers.count >= 2 {
            month = numbers[1]
        } else {
            month = nil
        }

        guard let finalMonth = month,
              day >= 1,
              day <= 31,
              finalMonth >= 1,
              finalMonth <= 12 else {
            return nil
        }

        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())

        var components = DateComponents()
        components.year = year
        components.month = finalMonth
        components.day = day

        guard let date = calendar.date(from: components) else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        return formatter.string(from: date)
    }

    private func parseTurkishTime(_ text: String) -> String? {
        let normalized = normalizeVoiceText(text)
        let numbers = extractNumbers(from: normalized)

        guard !numbers.isEmpty else {
            return nil
        }

        let hour = numbers[0]
        let minute = numbers.count >= 2 ? numbers[1] : 0

        guard hour >= 0,
              hour <= 23,
              minute >= 0,
              minute <= 59 else {
            return nil
        }

        return String(format: "%02d:%02d", hour, minute)
    }

    private func isSelectableAppointmentDate(_ backendDate: String) -> Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        guard let date = formatter.date(from: backendDate) else {
            return false
        }

        let calendar = Calendar.current
        let selectedDay = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())

        guard let lastSelectableDay = calendar.date(byAdding: .day, value: 13, to: today),
              selectedDay >= today,
              selectedDay <= lastSelectableDay else {
            return false
        }

        let weekday = calendar.component(.weekday, from: selectedDay)
        return weekday != 1 && weekday != 7
    }

    private func extractNumbers(from text: String) -> [Int] {
        var result: [Int] = []

        let tokens = text
            .replacingOccurrences(of: ":", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map(String.init)

        var index = 0

        while index < tokens.count {
            let token = tokens[index]

            if let number = Int(token) {
                result.append(number)
                index += 1
                continue
            }

            if token == "bucuk" {
                result.append(30)
                index += 1
                continue
            }

            guard let wordNumber = turkishNumberWordToInt(token) else {
                index += 1
                continue
            }

            if index + 1 < tokens.count,
               wordNumber >= 10,
               wordNumber % 10 == 0,
               let nextNumber = turkishNumberWordToInt(tokens[index + 1]),
               nextNumber > 0,
               nextNumber < 10 {
                result.append(wordNumber + nextNumber)
                index += 2
            } else {
                result.append(wordNumber)
                index += 1
            }
        }

        return result
    }

    private func turkishNumberWordToInt(_ word: String) -> Int? {
        let map: [String: Int] = [
            "sifir": 0,
            "bir": 1,
            "iki": 2,
            "uc": 3,
            "dort": 4,
            "bes": 5,
            "alti": 6,
            "yedi": 7,
            "sekiz": 8,
            "dokuz": 9,
            "on": 10,
            "onbir": 11,
            "oniki": 12,
            "onuc": 13,
            "ondort": 14,
            "onbes": 15,
            "onalti": 16,
            "onyedi": 17,
            "onsekiz": 18,
            "ondokuz": 19,
            "yirmi": 20,
            "otuz": 30,
            "kirk": 40,
            "elli": 50
        ]

        return map[word]
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

                    let weekday = Calendar.current.component(.weekday, from: date)
                    let isWeekend = weekday == 1 || weekday == 7

                    Button {
                        if !isWeekend {
                            selectedDate = backend
                            selectedTime = nil
                            onDateSelected(backend)
                        }
                    } label: {
                        VStack(spacing: 2) {
                            if isWeekend {
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }

                            Text("\(Calendar.current.component(.day, from: date))")
                                .font(.headline)
                        }
                        .frame(width: 42, height: 42)
                        .background(
                            isWeekend
                            ? Color.gray.opacity(0.18)
                            : isSelected
                                ? Color.red
                                : Color.white
                        )
                        .foregroundColor(
                            isWeekend
                            ? .gray
                            : isSelected
                                ? .white
                                : .primary
                        )
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(
                                    isWeekend
                                    ? Color.gray.opacity(0.4)
                                    : isSelected
                                        ? Color.red
                                        : Color.blue.opacity(0.35),
                                    lineWidth: 1.5
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isWeekend)
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
    @Published var emptySpeechCount = 0

    private let synthesizer = AVSpeechSynthesizer()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
    private let audioEngine = AVAudioEngine()

    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?

    private var lastText = ""
    private var shouldListenAfterSpeaking = false
    private var didCompleteCurrentListen = false
    private var isStoppingListening = false
    private var listeningGeneration = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func requestPermissionsIfNeeded() async -> Bool {
        let speechGranted: Bool

        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechGranted = true

        case .notDetermined:
            speechGranted = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }

        case .denied, .restricted:
            speechGranted = false

        @unknown default:
            speechGranted = false
        }

        let session = AVAudioSession.sharedInstance()
        let micGranted: Bool

        switch session.recordPermission {
        case .granted:
            micGranted = true

        case .undetermined:
            micGranted = await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }

        case .denied:
            micGranted = false

        @unknown default:
            micGranted = false
        }

        print("Speech izni:", speechGranted)
        print("Mikrofon izni:", micGranted)

        return speechGranted && micGranted
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
        didCompleteCurrentListen = true
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

        guard AVAudioSession.sharedInstance().recordPermission == .granted else {
            print("Mikrofon izni yok.")
            return
        }

        guard speechRecognizer?.isAvailable == true else {
            print("Speech recognizer hazır değil.")
            return
        }

        recognizedText = ""
        lastText = ""
        didCompleteCurrentListen = false

        stopListening()
        didCompleteCurrentListen = false
        listeningGeneration += 1
        let generation = listeningGeneration

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

        let request = recognitionRequest

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            guard buffer.frameLength > 0 else { return }
            request.append(buffer)
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
                guard generation == self.listeningGeneration else { return }
                guard !self.didCompleteCurrentListen else { return }

                if let result {
                    let text = result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    if !text.isEmpty {
                        self.lastText = text
                        self.restartSilenceTimer()
                    }
                }

                if let error {
                    guard !self.didCompleteCurrentListen else { return }

                    let message = error.localizedDescription

                    if message == "Recognition request was canceled" || self.isStoppingListening {
                        return
                    }

                    print("Speech hata:", message)

                    if self.lastText.isEmpty {
                        self.stopListening()
                        self.emptySpeechCount += 1
                    } else {
                        self.finishListening()
                    }
                }
            }
        }
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
        guard !didCompleteCurrentListen else { return }

        let finalText = lastText.trimmingCharacters(in: .whitespacesAndNewlines)

        didCompleteCurrentListen = true

        guard !finalText.isEmpty else {
            stopListening()
            print("Ses boş geldi.")
            emptySpeechCount += 1
            return
        }

        stopListening()
        print("ALGILANAN SES:", finalText)
        recognizedText = finalText
    }

    private func stopListening() {
        isStoppingListening = true
        listeningGeneration += 1
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
        isStoppingListening = false
    }
}

#Preview {
    NavigationStack {
        HastaneRandevuView(userId: 1, initialClinic: nil)
    }
}
