import SwiftUI

// MARK: - DTO
struct FamilyDoctorUserDTO: Codable {
    let id: Int?
    let name: String?
    let surname: String?
    let familyDoctor: FamilyDoctorDTO?
}

struct FamilyDoctorDTO: Codable {
    let id: Int?
    let name: String?
    let specialization: String?
    let clinic: FamilyClinicDTO?
}

struct FamilyClinicDTO: Codable {
    let id: Int?
    let name: String?
    let location: String?
}
struct CreateFamilyAppointmentRequest: Encodable {
    let user: AppointmentIdDTO
    let doctor: AppointmentIdDTO
    let appointmentDateTime: String
    let notes: String?
}
// MARK: - API
enum FamilyDoctorAPI {
    static func getUser(userId: Int) async throws -> FamilyDoctorUserDTO {
        let url = APIConfig.userDetailURL(userId: userId)

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(FamilyDoctorUserDTO.self, from: data)
    }

    static func userAppointments(userId: Int) async throws -> [AppointmentDTO] {
        let url = APIConfig.appointmentsByUserURL(userId: userId)
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([AppointmentDTO].self, from: data)
    }

    static func createAppointment(_ body: CreateFamilyAppointmentRequest) async throws {
        var request = URLRequest(url: APIConfig.createFamilyAppointmentURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = String(data: data, encoding: .utf8) ?? "Randevu oluşturulamadı."
            throw NSError(
                domain: "",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }
}
struct AileHekimiRandevuView: View {
    let userId: Int

    @Environment(\.dismiss) private var dismiss

    @State private var familyDoctor: FamilyDoctorDTO?
    @State private var isLoading = false
    @State private var alertMessage: String?
    @State private var showRandevuView = false
    @State private var selectedType = "Aile Hekimi Muayene"

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

            Text("Aile Hekimi Randevu Sistemi")
                .font(.title2.bold())

            if isLoading {
                ProgressView("Aile hekimi bilgileri yükleniyor...")
                    .padding()
            } else if let familyDoctor {
                VStack(alignment: .leading, spacing: 14) {
                    InfoRow(icon: "person.crop.circle", text: familyDoctor.name ?? "Aile hekimi bilgisi yok")
                    InfoRow(icon: "stethoscope", text: familyDoctor.specialization ?? "Uzmanlık bilgisi yok")
                    InfoRow(icon: "building.columns", text: familyDoctor.clinic?.name ?? "Klinik bilgisi yok")
                    InfoRow(icon: "mappin.and.ellipse", text: familyDoctor.clinic?.location ?? "Adres bilgisi yok")
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .cornerRadius(18)
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)

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
            } else {
                Text("Aile hekimi bilgisi bulunamadı.")
                    .foregroundColor(.gray)
                    .padding()
            }

            Spacer()
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .task {
            await loadFamilyDoctor()
        }
        .sheet(isPresented: $showRandevuView) {
            if let familyDoctor {
                AileHekimiRandevuOlusturView(
                    userId: userId,
                    appointmentType: selectedType,
                    familyDoctor: familyDoctor
                )
            }
        }
        .alert("Uyarı", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("Tamam") {
                alertMessage = nil
            }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    @MainActor
    private func loadFamilyDoctor() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let user = try await FamilyDoctorAPI.getUser(userId: userId)

            guard let doctor = user.familyDoctor else {
                alertMessage = "Aile hekiminiz bulunamadı."
                return
            }

            familyDoctor = doctor
        } catch {
            alertMessage = "Aile hekimi bilgileri alınamadı."
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

            Spacer()
        }
    }
}
// MARK: - View
struct AileHekimiRandevuOlusturView: View {
    let userId: Int
    let appointmentType: String
    let familyDoctor: FamilyDoctorDTO

    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate: String?
    @State private var selectedTime: String?
    @State private var alertMessage: String?
    @State private var isSaving = false
    @State private var existingAppointments: [AppointmentDTO] = []

    private let times = [
        "09:00", "09:30", "10:00", "10:30",
        "11:00", "11:30", "13:00", "13:30",
        "14:00", "14:30", "15:00", "15:30"
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                FamilyWeekdayCalendarView(
                    selectedDate: $selectedDate,
                    selectedTime: $selectedTime
                )

                if selectedDate != nil {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible()), count: 3),
                        spacing: 12
                    ) {
                        ForEach(times, id: \.self) { time in
                            let available = isTimeAvailable(time)
                            let selected = selectedTime == time

                            Button {
                                if available {
                                    selectedTime = time
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    if selected {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                    }

                                    if !available {
                                        Image(systemName: "lock.fill")
                                            .font(.caption2)
                                    }

                                    Text(time)
                                        .font(.headline)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(
                                    selected
                                    ? Color.red
                                    : available
                                        ? Color.white
                                        : Color.gray.opacity(0.2)
                                )
                                .foregroundColor(
                                    selected
                                    ? .white
                                    : available
                                        ? .blue
                                        : .gray
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(
                                            selected
                                            ? Color.red
                                            : available
                                                ? Color.blue
                                                : Color.gray.opacity(0.35),
                                            lineWidth: 1.5
                                        )
                                )
                                .cornerRadius(14)
                            }
                            .disabled(!available)
                        }
                    }
                }

                Button {
                    Task {
                        await createAppointment()
                    }
                } label: {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                    } else {
                        Text("Randevuyu Onayla")
                            .font(.headline.bold())
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                    }
                }
                .background(
                    selectedDate != nil && selectedTime != nil
                    ? Color.blue
                    : Color.gray.opacity(0.35)
                )
                .foregroundColor(.white)
                .cornerRadius(18)
                .disabled(isSaving || selectedDate == nil || selectedTime == nil)

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
            .task {
                await loadExistingAppointments()
            }
            .alert("Uyarı", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("Tamam") {
                    if alertMessage == "Randevunuz başarıyla oluşturuldu." {
                        dismiss()
                    }
                    alertMessage = nil
                }
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private func isTimeAvailable(_ time: String) -> Bool {
        guard let selectedDate else { return false }

        return !existingAppointments.contains { appointment in
            let status = appointment.status?.uppercased() ?? ""

            let iptalDegil =
                status != "CANCELLED" &&
                status != "CANCELED" &&
                status != "İPTAL" &&
                status != "IPTAL"

            let sameDoctor = appointment.doctor?.id == familyDoctor.id
            let sameDateTime = appointment.appointmentDateTime == "\(selectedDate)T\(time):00"

            return sameDoctor && sameDateTime && iptalDegil
        }
    }

    @MainActor
    private func loadExistingAppointments() async {
        do {
            existingAppointments = try await FamilyDoctorAPI.userAppointments(userId: userId)
        } catch {
            print("Aile hekimi randevuları alınamadı:", error.localizedDescription)
        }
    }

    @MainActor
    private func createAppointment() async {
        guard let selectedDate, let selectedTime else {
            alertMessage = "Lütfen tarih ve saat seçiniz."
            return
        }

        guard isTimeAvailable(selectedTime) else {
            alertMessage = "Bu saat dolu. Lütfen başka bir saat seçiniz."
            return
        }

        isSaving = true
        defer { isSaving = false }

        let dateTime = "\(selectedDate)T\(selectedTime):00"

        let body = CreateFamilyAppointmentRequest(
            user: AppointmentIdDTO(id: userId),
            doctor: AppointmentIdDTO(id: familyDoctor.id ?? 0),
            appointmentDateTime: dateTime,
            notes: appointmentType
        )

        do {
            try await FamilyDoctorAPI.createAppointment(body)
            await loadExistingAppointments()
            alertMessage = "Randevunuz başarıyla oluşturuldu."
        } catch {
            print("Aile hekimi randevu hatası:", error.localizedDescription)
            alertMessage = error.localizedDescription
        }
    }
}
struct FamilyWeekdayCalendarView: View {
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
                        guard !isWeekend else { return }

                        selectedDate = backend
                        selectedTime = nil
                    } label: {
                        VStack(spacing: 2) {
                            if isWeekend {
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
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
        .cornerRadius(18)
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
