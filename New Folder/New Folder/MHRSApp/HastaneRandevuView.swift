import SwiftUI

// MARK: - DTO'lar

struct IlDTO: Identifiable, Decodable, Hashable {
    let id: Int
    let ad: String
}

struct IlceDTO: Identifiable, Decodable, Hashable {
    let id: Int
    let ad: String
    let il_id: Int
}

struct HastaneDTO: Identifiable, Decodable, Hashable {
    let id: Int
    let ad: String
    let ilce_id: Int?
}

struct HastaneDoctorDTO: Identifiable, Decodable, Hashable {
    let id: Int
    let doktor_ad: String
    let hastane_id: Int?
    let hastane_ad: String?
}

// MARK: - UI Models

struct TimeSlotUI: Identifiable, Hashable {
    let id = UUID()
    let time: String
    let available: Bool
}

// MARK: - Mock API

enum MockAppointmentAPI {

    static func cities() async throws -> [IlDTO] {
        [
            IlDTO(id: 1, ad: "Trabzon"),
            IlDTO(id: 2, ad: "İstanbul"),
            IlDTO(id: 3, ad: "Ankara")
        ]
    }

    static func districts(il: IlDTO) async throws -> [IlceDTO] {
        switch il.ad {
        case "Trabzon":
            return [
                IlceDTO(id: 1, ad: "Ortahisar", il_id: il.id),
                IlceDTO(id: 2, ad: "Akçaabat", il_id: il.id)
            ]
        case "İstanbul":
            return [
                IlceDTO(id: 3, ad: "Kadıköy", il_id: il.id),
                IlceDTO(id: 4, ad: "Üsküdar", il_id: il.id)
            ]
        case "Ankara":
            return [
                IlceDTO(id: 5, ad: "Çankaya", il_id: il.id),
                IlceDTO(id: 6, ad: "Keçiören", il_id: il.id)
            ]
        default:
            return []
        }
    }

    static func hospitals(ilce: IlceDTO) async throws -> [HastaneDTO] {
        [
            HastaneDTO(id: 1, ad: "\(ilce.ad) Devlet Hastanesi", ilce_id: ilce.id),
            HastaneDTO(id: 2, ad: "\(ilce.ad) Eğitim ve Araştırma Hastanesi", ilce_id: ilce.id)
        ]
    }

    static func doctors(hastane: HastaneDTO) async throws -> [HastaneDoctorDTO] {
        [
            HastaneDoctorDTO(id: 1, doktor_ad: "Dr. Ahmet Yılmaz", hastane_id: hastane.id, hastane_ad: hastane.ad),
            HastaneDoctorDTO(id: 2, doktor_ad: "Dr. Ayşe Demir", hastane_id: hastane.id, hastane_ad: hastane.ad),
            HastaneDoctorDTO(id: 3, doktor_ad: "Dr. Mehmet Kaya", hastane_id: hastane.id, hastane_ad: hastane.ad)
        ]
    }
}

// MARK: - View

struct HastaneRandevuView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var iller: [IlDTO] = []
    @State private var ilceler: [IlceDTO] = []
    @State private var hastaneler: [HastaneDTO] = []
    @State private var doktorlar: [HastaneDoctorDTO] = []

    @State private var secilenIl: IlDTO?
    @State private var secilenIlce: IlceDTO?
    @State private var secilenHastane: HastaneDTO?
    @State private var secilenDoktor: HastaneDoctorDTO?

    @State private var secilenKlinik = ""
    @State private var secilenMuayeneYeri = ""

    @State private var showCalendar = false
    @State private var selectedDate: String?
    @State private var selectedTime: String?

    @State private var alertMessage: String?

    let klinikler = [
        "",
        "Aile Hekimliği",
        "Kardiyoloji",
        "Nöroloji",
        "Fizik Tedavi ve Rehabilitasyon",
        "Dahiliye",
        "Göz Hastalıkları"
    ]

    let muayeneYerleri = [
        "",
        "Poliklinik 1",
        "Poliklinik 2",
        "Acil",
        "Muayene Odası 3"
    ]

    private var availableTimes: [String] {
        [
            "09:00", "09:10", "09:30",
            "10:00", "10:20", "10:40",
            "11:00", "11:30",
            "13:00", "13:20",
            "14:00", "14:30",
            "15:00", "15:40",
            "16:20"
        ]
    }

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
            await illeriYukle()
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

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(secilenDoktor?.doktor_ad ?? "Doktor Seçimi")
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
                    Text("Seçiniz").tag(nil as IlDTO?)
                    ForEach(iller) { il in
                        Text(il.ad).tag(Optional(il))
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
                    resetDateSelection()

                    guard let yeniIl else { return }

                    do {
                        ilceler = try await MockAppointmentAPI.districts(il: yeniIl)
                    } catch {
                        print("İlçe yükleme hatası:", error)
                    }
                }
            }

            divider

            pickerRow(title: "İlçe") {
                Picker("İlçe", selection: $secilenIlce) {
                    Text("Seçiniz").tag(nil as IlceDTO?)
                    ForEach(ilceler) { ilce in
                        Text(ilce.ad).tag(Optional(ilce))
                    }
                }
                .pickerStyle(.menu)
            }
            .onChange(of: secilenIlce) { _, yeniIlce in
                Task {
                    secilenHastane = nil
                    hastaneler = []
                    secilenDoktor = nil
                    doktorlar = []
                    resetDateSelection()

                    guard let yeniIlce else { return }

                    do {
                        hastaneler = try await MockAppointmentAPI.hospitals(ilce: yeniIlce)
                    } catch {
                        print("Hastane yükleme hatası:", error)
                    }
                }
            }

            divider

            pickerRow(title: "Hastane") {
                Picker("Hastane", selection: $secilenHastane) {
                    Text("Seçiniz").tag(nil as HastaneDTO?)
                    ForEach(hastaneler) { hastane in
                        Text(hastane.ad).tag(Optional(hastane))
                    }
                }
                .pickerStyle(.menu)
            }
            .onChange(of: secilenHastane) { _, yeniHastane in
                Task {
                    secilenDoktor = nil
                    doktorlar = []
                    resetDateSelection()

                    guard let yeniHastane else { return }

                    do {
                        doktorlar = try await MockAppointmentAPI.doctors(hastane: yeniHastane)
                    } catch {
                        print("Doktor yükleme hatası:", error)
                    }
                }
            }

            divider

            pickerRow(title: "Klinik") {
                Picker("Klinik", selection: $secilenKlinik) {
                    ForEach(klinikler, id: \.self) { klinik in
                        Text(klinik.isEmpty ? "Seçiniz" : klinik).tag(klinik)
                    }
                }
                .pickerStyle(.menu)
            }
            .onChange(of: secilenKlinik) { _, _ in
                resetDateSelection()
            }

            divider

            pickerRow(title: "Doktor") {
                Picker("Doktor", selection: $secilenDoktor) {
                    Text("Seçiniz").tag(nil as HastaneDoctorDTO?)
                    ForEach(doktorlar) { doktor in
                        Text(doktor.doktor_ad).tag(Optional(doktor))
                    }
                }
                .pickerStyle(.menu)
            }
            .onChange(of: secilenDoktor) { _, _ in
                resetDateSelection()
            }

            divider

            pickerRow(title: "Muayene Yeri") {
                Picker("Muayene Yeri", selection: $secilenMuayeneYeri) {
                    ForEach(muayeneYerleri, id: \.self) { yer in
                        Text(yer.isEmpty ? "Seçiniz" : yer).tag(yer)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 3)
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

    private var dateTimeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tarih Seçiniz")
                .font(.headline)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)

            CalendarGridView(
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

    private func illeriYukle() async {
        do {
            iller = try await MockAppointmentAPI.cities()
        } catch {
            print("İl yükleme hatası:", error)
        }
    }

    private func randevuAra() {
        guard secilenIl != nil,
              secilenIlce != nil,
              secilenHastane != nil,
              secilenDoktor != nil,
              !secilenKlinik.isEmpty else {
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
        guard let selectedDate,
              let selectedTime else {
            alertMessage = "Lütfen tarih ve saat seçiniz."
            return
        }

        alertMessage = "Randevunuz oluşturuldu: \(selectedDate) saat \(selectedTime)"
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
        secilenHastane = nil
        hastaneler = []
        secilenDoktor = nil
        doktorlar = []
        secilenKlinik = ""
        secilenMuayeneYeri = ""
        resetDateSelection()
    }
}

// MARK: - Calendar

struct CalendarGridView: View {
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
                    } label: {
                        Text("\(Calendar.current.component(.day, from: date))")
                            .font(.headline)
                            .frame(width: 42, height: 42)
                            .background(isSelected ? Color.red : Color.white)
                            .foregroundColor(isSelected ? .white : .primary)
                            .overlay(
                                Circle()
                                    .stroke(isSelected ? Color.red : Color.blue.opacity(0.3), lineWidth: 1.5)
                            )
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.blue.opacity(0.35), lineWidth: 1)
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

#Preview {
    NavigationStack {
        HastaneRandevuView()
    }
}
