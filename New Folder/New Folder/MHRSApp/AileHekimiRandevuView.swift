import SwiftUI
import AVFoundation
import Speech
import Foundation

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

// MARK: - Voice Manager

final class FamilyAppointmentVoiceManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    enum Step {
        case idle
        case askingVoicePermission
        case listeningVoicePermission
        case askingCreateAppointment
        case listeningCreateAppointment
        case askingDate
        case listeningDate
        case askingTime
        case listeningTime
    }

    @Published var isListening = false

    var onManualMode: (() -> Void)?
    var onVoiceAccepted: (() -> Void)?
    var onCreateAppointmentConfirmed: (() -> Void)?
    var onDateText: ((String) -> Void)?
    var onTimeText: ((String) -> Void)?

    private var step: Step = .idle
    private var didHandleCurrentSpeech = false
    private var pendingRecognitionWorkItem: DispatchWorkItem?

    private let synthesizer = AVSpeechSynthesizer()
    
    
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))

    
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    override init() {
        super.init()
        synthesizer.delegate = self

        SFSpeechRecognizer.requestAuthorization { status in
            print("Family speech permission:", status.rawValue)
        }

        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            print("Family mic permission:", granted)
        }
    }

    func startInitialFlow() {
        stopListening()

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        step = .askingVoicePermission
        speak("Sesli komutla devam etmek ister misiniz?")
    }

    func askCreateAppointment(doctorName: String) {
        step = .askingCreateAppointment
        speak("Aile hekiminiz \(doctorName). Bu doktordan randevu oluşturmak ister misiniz?")
    }
    func askDate() {
        step = .askingDate
        speak("Randevu tarihi söyleyiniz.")
    }

    func askTime() {
        step = .askingTime
        speak("Randevu saati söyleyiniz.")
    }


    func speak(_ text: String) {
        stopListening()

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Family TTS session hata:", error.localizedDescription)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "tr-TR")
        utterance.rate = 0.45
        utterance.volume = 1.0

        synthesizer.speak(utterance)
    }

    func stopAll() {
        pendingRecognitionWorkItem?.cancel()
        pendingRecognitionWorkItem = nil

        synthesizer.stopSpeaking(at: .immediate)
        stopListening()

        step = .idle
        didHandleCurrentSpeech = false
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        switch step {
        case .askingVoicePermission:
            step = .listeningVoicePermission
            startListeningAfterDelay()

        case .askingCreateAppointment:
            step = .listeningCreateAppointment
            startListeningAfterDelay()

        case .askingDate:
            step = .listeningDate
            startListeningAfterDelay()

        case .askingTime:
            step = .listeningTime
            startListeningAfterDelay()

        default:
            break
        }
    }

    private func startListeningAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard !self.synthesizer.isSpeaking else { return }
            self.startListening()
        }
    }

    private func startListening() {
        stopListening()
        didHandleCurrentSpeech = false
        pendingRecognitionWorkItem?.cancel()
        pendingRecognitionWorkItem = nil

        guard recognizer?.isAvailable == true else {
            print("Speech recognizer uygun değil.")
            onManualMode?()
            return
        }

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.reset()
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .duckOthers, .allowBluetooth]
            )
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Family audio session hata:", error.localizedDescription)
            onManualMode?()
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest else {
            onManualMode?()
            return
        }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation
        recognitionRequest.contextualStrings = [
            "evet", "hayır", "hayir", "manuel",
            "bugün", "bugun", "yarın", "yarin",
            "pazartesi", "salı", "sali", "çarşamba", "carsamba",
            "perşembe", "persembe", "cuma",
            "ocak", "şubat", "subat", "mart", "nisan", "mayıs", "mayis",
            "haziran", "temmuz", "ağustos", "agustos",
            "eylül", "eylul", "ekim", "kasım", "kasim", "aralık", "aralik",
            "on beş mayıs", "15 mayıs", "on bes mayis",
            "dokuz", "dokuz otuz", "on", "on otuz",
            "on bir", "on bir otuz",
            "on üç", "on uc", "on üç otuz", "on uc otuz",
            "on dört", "on dort", "on dört otuz", "on dort otuz",
            "on beş", "on bes", "on beş otuz", "on bes otuz"
        ]

        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)

        let format = inputNode.inputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            print("Mikrofon formatı geçersiz:", format)
            onManualMode?()
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
            DispatchQueue.main.async {
                self.isListening = true
            }
        } catch {
            print("Audio engine hata:", error.localizedDescription)
            onManualMode?()
            return
        }

        recognitionTask = recognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString.lowercased()
                print("Aile hekimi algılanan:", text)

                if self.didHandleCurrentSpeech {
                    return
                }

                DispatchQueue.main.async {
                    self.scheduleHandle(text)
                }
            }

            if error != nil && !self.didHandleCurrentSpeech {
                DispatchQueue.main.async {
                    self.stopListening()
                }
            }
        }
    }

    private func scheduleHandle(_ text: String) {
        let normalized = normalizeTurkish(text)

        guard shouldAccept(normalized) else {
            return
        }

        pendingRecognitionWorkItem?.cancel()

        let delay: TimeInterval

        switch step {
        case .listeningVoicePermission, .listeningCreateAppointment:
            delay = 0.25
        case .listeningDate, .listeningTime:
            delay = 1.0
        default:
            delay = 0.5
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }

            if self.didHandleCurrentSpeech {
                return
            }

            self.didHandleCurrentSpeech = true
            self.handle(normalized)
        }

        pendingRecognitionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func stopListening() {
        pendingRecognitionWorkItem?.cancel()
        pendingRecognitionWorkItem = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.reset()
        }

        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        DispatchQueue.main.async {
            self.isListening = false
        }
    }

    private func shouldAccept(_ text: String) -> Bool {
        switch step {
        case .listeningVoicePermission, .listeningCreateAppointment:
            return isYes(text) || isNo(text)

        case .listeningDate:
            return text.contains("bugun") ||
            text.contains("yarin") ||
            text.contains("pazartesi") ||
            text.contains("sali") ||
            text.contains("carsamba") ||
            text.contains("persembe") ||
            text.contains("cuma") ||
            containsMonth(text) ||
            text.rangeOfCharacter(from: .decimalDigits) != nil

        case .listeningTime:
            return text.contains("dokuz") ||
            text.contains("on") ||
            text.contains("otuz") ||
            text.contains("bucuk") ||
            text.rangeOfCharacter(from: .decimalDigits) != nil

        default:
            return false
        }
    }

    private func handle(_ text: String) {
        switch step {
        case .listeningVoicePermission:
            if isYes(text) {
                stopListening()
                step = .idle
                onVoiceAccepted?()
            } else if isNo(text) {
                stopListening()
                step = .idle
                speak("Tamam, manuel olarak devam edebilirsiniz.")
                onManualMode?()
            }

        case .listeningCreateAppointment:
            if isYes(text) {
                stopListening()
                step = .idle
                onCreateAppointmentConfirmed?()
            } else if isNo(text) {
                stopListening()
                step = .idle
                speak("Tamam, manuel olarak devam edebilirsiniz.")
                onManualMode?()
            }

        case .listeningDate:
            stopListening()
            step = .idle
            onDateText?(text)

        case .listeningTime:
            stopListening()
            step = .idle
            onTimeText?(text)

        default:
            break
        }
    }

    private func isYes(_ text: String) -> Bool {
        text.contains("evet") ||
        text.contains("olur") ||
        text.contains("tamam")
    }

    private func isNo(_ text: String) -> Bool {
        text.contains("hayir") ||
        text.contains("manuel") ||
        text.contains("istemiyorum")
    }

    private func containsMonth(_ text: String) -> Bool {
        text.contains("ocak") ||
        text.contains("subat") ||
        text.contains("mart") ||
        text.contains("nisan") ||
        text.contains("mayis") ||
        text.contains("haziran") ||
        text.contains("temmuz") ||
        text.contains("agustos") ||
        text.contains("eylul") ||
        text.contains("ekim") ||
        text.contains("kasim") ||
        text.contains("aralik")
    }

    private func normalizeTurkish(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "ğ", with: "g")
            .replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: "ş", with: "s")
            .replacingOccurrences(of: "ö", with: "o")
            .replacingOccurrences(of: "ç", with: "c")
    }
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
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

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

// MARK: - Main View

struct AileHekimiRandevuView: View {
    let userId: Int
    var startWithVoice: Bool = true

    @Environment(\.dismiss) private var dismiss

    @StateObject private var voiceManager = FamilyAppointmentVoiceManager()

    @State private var familyDoctor: FamilyDoctorDTO?
    @State private var isLoading = false
    @State private var alertMessage: String?
    @State private var showRandevuView = false
    @State private var selectedType = "Aile Hekimi Muayene"
    @State private var startCreateViewWithVoice = false
    @State private var didStartVoiceFlow = false

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button {
                    voiceManager.stopAll()
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
                    voiceManager.stopAll()
                    selectedType = "Aile Hekimi Muayene"
                    startCreateViewWithVoice = false
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
            setupVoiceCallbacks()
            await loadFamilyDoctor()

            if startWithVoice && !didStartVoiceFlow {
                didStartVoiceFlow = true

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    voiceManager.startInitialFlow()
                }
            }
        }

        .sheet(isPresented: $showRandevuView) {
            if let familyDoctor {
                AileHekimiRandevuOlusturView(
                    userId: userId,
                    appointmentType: selectedType,
                    familyDoctor: familyDoctor,
                    startWithVoice: startCreateViewWithVoice,
                    onAppointmentCreated: {
                        voiceManager.stopAll()
                        dismiss()
                    }
                )
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
                alertMessage = nil
            }
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func setupVoiceCallbacks() {
        voiceManager.onManualMode = {
            DispatchQueue.main.async {
                voiceManager.stopListening()
            }
        }

        voiceManager.onVoiceAccepted = {
            DispatchQueue.main.async {
                guard let familyDoctor else {
                    voiceManager.speak("Aile hekiminiz bulunamadı. Manuel olarak devam edebilirsiniz.")
                    return
                }

                voiceManager.askCreateAppointment(
                    doctorName: familyDoctor.name ?? "aile hekiminiz"
                )
            }
        }

        voiceManager.onCreateAppointmentConfirmed = {
            DispatchQueue.main.async {
                selectedType = "Aile Hekimi Muayene"
                startCreateViewWithVoice = true
                showRandevuView = true
            }
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
            print("Aile hekimi bilgileri alınamadı:", error.localizedDescription)
            alertMessage = "Aile hekimi bilgileri alınamadı."
        }
    }
}

// MARK: - Info Row

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

// MARK: - Create Appointment View

struct AileHekimiRandevuOlusturView: View {
    let userId: Int
    let appointmentType: String
    let familyDoctor: FamilyDoctorDTO
    let startWithVoice: Bool
    let onAppointmentCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var voiceManager = FamilyAppointmentVoiceManager()

    @State private var selectedDate: String?
    @State private var selectedTime: String?
    @State private var alertMessage: String?
    @State private var isSaving = false
    @State private var existingAppointments: [AppointmentDTO] = []
    @State private var didStartVoiceFlow = false

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
                        voiceManager.stopAll()
                        dismiss()
                    }
                }
            }
            .task {
                setupVoiceCallbacks()
                await loadExistingAppointments()

                if startWithVoice && !didStartVoiceFlow {
                    didStartVoiceFlow = true

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        voiceManager.askDate()
                    }
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
                    alertMessage = nil
                }
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private func setupVoiceCallbacks() {
        voiceManager.onManualMode = {
            DispatchQueue.main.async {
                voiceManager.stopListening()
            }
        }

        voiceManager.onDateText = { text in
            DispatchQueue.main.async {
                handleVoiceDate(text)
            }
        }

        voiceManager.onTimeText = { text in
            DispatchQueue.main.async {
                handleVoiceTime(text)
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

    private func handleVoiceDate(_ text: String) {
        guard let date = resolveVoiceDate(text) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
                voiceManager.askDate()
            }
            return
        }

        selectedDate = date
        selectedTime = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            voiceManager.askTime()
        }
    }

    private func handleVoiceTime(_ text: String) {
        guard let time = resolveVoiceTime(text) else {
            voiceManager.speak("Saati anlayamadım. Lütfen dokuz, dokuz otuz veya on üç otuz gibi söyleyiniz.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
                voiceManager.askTime()
            }
            return
        }

        guard isTimeAvailable(time) else {
            voiceManager.speak("Bu saat dolu. Lütfen başka bir saat söyleyiniz.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                voiceManager.askTime()
            }
            return
        }

        selectedTime = time

        Task {
            await createAppointment()
        }
    }

    private func resolveVoiceDate(_ text: String) -> String? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let normalized = normalizeTurkish(text)

        let targetDate: Date?

        if normalized.contains("bugun") {
            targetDate = today
        } else if normalized.contains("yarin") {
            targetDate = calendar.date(byAdding: .day, value: 1, to: today)
        } else if let dayMonthDate = resolveDayMonthDate(from: normalized) {
            targetDate = dayMonthDate
        } else {
            targetDate = nextWeekdayDate(from: normalized)
        }

        guard let targetDate else {
            voiceManager.speak("Tarihi anlayamadım. Örneğin on beş mayıs veya 15 mayıs diyebilirsiniz.")
            return nil
        }

        guard targetDate >= today else {
            voiceManager.speak("Geçmiş tarihe randevu alınamaz. Lütfen ileri bir tarih söyleyiniz.")
            return nil
        }

        let maxDate = calendar.date(byAdding: .day, value: 13, to: today) ?? today

        guard targetDate <= maxDate else {
            voiceManager.speak("Sadece önümüzdeki on dört gün için randevu alınabilir. Lütfen daha yakın bir tarih söyleyiniz.")
            return nil
        }

        let weekday = calendar.component(.weekday, from: targetDate)
        let isWeekend = weekday == 1 || weekday == 7

        if isWeekend {
            voiceManager.speak("Hafta sonu randevu alınamaz. Lütfen hafta içi bir gün söyleyiniz.")
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "yyyy-MM-dd"

        return formatter.string(from: targetDate)
    }

    private func resolveVoiceTime(_ text: String) -> String? {
        let normalized = normalizeTurkish(text)
            .replacingOccurrences(of: ".", with: ":")
            .replacingOccurrences(of: ",", with: ":")
            .replacingOccurrences(of: "saat", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for time in times {
            if normalized.contains(time) {
                return time
            }
        }

        let hour: String?

        if normalized.contains("dokuz") || normalized.contains("9") {
            hour = "09"
        } else if normalized.contains("on bes") || normalized.contains("15") {
            hour = "15"
        } else if normalized.contains("on dort") || normalized.contains("14") {
            hour = "14"
        } else if normalized.contains("on uc") || normalized.contains("13") {
            hour = "13"
        } else if normalized.contains("on bir") || normalized.contains("11") {
            hour = "11"
        } else if normalized.contains("on") || normalized.contains("10") {
            hour = "10"
        } else {
            hour = nil
        }

        guard let hour else {
            return nil
        }

        let minute =
            normalized.contains("otuz") ||
            normalized.contains("bucuk") ||
            normalized.contains("buçuk")
            ? "30"
            : "00"

        let time = "\(hour):\(minute)"
        return times.contains(time) ? time : nil
    }

    private func resolveDayMonthDate(from text: String) -> Date? {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())

        guard let month = monthNumber(from: text),
              let day = dayNumber(from: text) else {
            return nil
        }

        var components = DateComponents()
        components.year = currentYear
        components.month = month
        components.day = day

        guard let dateThisYear = calendar.date(from: components),
              calendar.component(.month, from: dateThisYear) == month,
              calendar.component(.day, from: dateThisYear) == day else {
            return nil
        }

        let today = calendar.startOfDay(for: Date())

        if dateThisYear >= today {
            return calendar.startOfDay(for: dateThisYear)
        }

        components.year = currentYear + 1

        guard let dateNextYear = calendar.date(from: components),
              calendar.component(.month, from: dateNextYear) == month,
              calendar.component(.day, from: dateNextYear) == day else {
            return nil
        }

        return calendar.startOfDay(for: dateNextYear)
    }

    private func nextWeekdayDate(from text: String) -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let targetWeekday: Int?

        if text.contains("pazartesi") {
            targetWeekday = 2
        } else if text.contains("sali") {
            targetWeekday = 3
        } else if text.contains("carsamba") {
            targetWeekday = 4
        } else if text.contains("persembe") {
            targetWeekday = 5
        } else if text.contains("cuma") {
            targetWeekday = 6
        } else {
            targetWeekday = nil
        }

        guard let targetWeekday else {
            return nil
        }

        for offset in 0..<14 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else {
                continue
            }

            if calendar.component(.weekday, from: date) == targetWeekday {
                return date
            }
        }

        return nil
    }

    private func monthNumber(from text: String) -> Int? {
        if text.contains("ocak") { return 1 }
        if text.contains("subat") { return 2 }
        if text.contains("mart") { return 3 }
        if text.contains("nisan") { return 4 }
        if text.contains("mayis") { return 5 }
        if text.contains("haziran") { return 6 }
        if text.contains("temmuz") { return 7 }
        if text.contains("agustos") { return 8 }
        if text.contains("eylul") { return 9 }
        if text.contains("ekim") { return 10 }
        if text.contains("kasim") { return 11 }
        if text.contains("aralik") { return 12 }
        return nil
    }

    private func dayNumber(from text: String) -> Int? {
        if let numericDay = extractNumericDay(from: text) {
            return numericDay
        }

        let numberWords: [(String, Int)] = [
            ("otuz bir", 31),
            ("otuz", 30),
            ("yirmi dokuz", 29),
            ("yirmi sekiz", 28),
            ("yirmi yedi", 27),
            ("yirmi alti", 26),
            ("yirmi bes", 25),
            ("yirmi dort", 24),
            ("yirmi uc", 23),
            ("yirmi iki", 22),
            ("yirmi bir", 21),
            ("yirmi", 20),
            ("on dokuz", 19),
            ("on sekiz", 18),
            ("on yedi", 17),
            ("on alti", 16),
            ("on bes", 15),
            ("on dort", 14),
            ("on uc", 13),
            ("on iki", 12),
            ("on bir", 11),
            ("on", 10),
            ("dokuz", 9),
            ("sekiz", 8),
            ("yedi", 7),
            ("alti", 6),
            ("bes", 5),
            ("dort", 4),
            ("uc", 3),
            ("iki", 2),
            ("bir", 1)
        ]

        for (word, value) in numberWords {
            if text.contains(word) {
                return value
            }
        }

        return nil
    }

    private func extractNumericDay(from text: String) -> Int? {
        let parts = text.split(separator: " ")

        for part in parts {
            let cleaned = part.filter { $0.isNumber }

            if let day = Int(cleaned), 1...31 ~= day {
                return day
            }
        }

        return nil
    }

    private func normalizeTurkish(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "ğ", with: "g")
            .replacingOccurrences(of: "ü", with: "u")
            .replacingOccurrences(of: "ş", with: "s")
            .replacingOccurrences(of: "ö", with: "o")
            .replacingOccurrences(of: "ç", with: "c")
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

        guard let doctorId = familyDoctor.id else {
            alertMessage = "Doktor bilgisi eksik."
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
            doctor: AppointmentIdDTO(id: doctorId),
            appointmentDateTime: dateTime,
            notes: appointmentType
        )

        do {
            try await FamilyDoctorAPI.createAppointment(body)
            await loadExistingAppointments()

            voiceManager.speak("Randevunuz başarıyla oluşturuldu. Ana sayfaya dönülüyor.")

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                voiceManager.stopAll()
                dismiss()
                onAppointmentCreated()
            }

        } catch {
            print("Aile hekimi randevu hatası:", error.localizedDescription)
            voiceManager.speak("Randevu oluşturulamadı.")
            alertMessage = error.localizedDescription
        }
    }
}

// MARK: - Calendar

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
