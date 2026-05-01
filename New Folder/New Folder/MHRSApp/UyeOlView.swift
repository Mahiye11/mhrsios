import SwiftUI
import Foundation

struct RegisterRequest: Codable {
    let name: String
    let surname: String
    let tcKimlik: String
    let password: String
    let cinsiyet: String
    let dogumTarihi: String
}

struct RegisterResponse: Codable {
    let message: String?
    let userId: Int?
    let tcKimlik: String?
    let name: String?
}

struct UyeOlView: View {
    @Environment(\.dismiss) private var dismiss

    enum Field: Hashable {
        case ad, soyad, tc, sifre
    }

    enum RegisterMode {
        case manual
        case voice
    }

    @FocusState private var focused: Field?

    @State private var registerMode: RegisterMode? = nil
    @StateObject private var voiceRegisterVM = VoiceRegisterManager()

    @State private var ad = ""
    @State private var soyad = ""
    @State private var tc = ""
    @State private var sifre = ""
    @State private var cinsiyet = ""
    @State private var dogumTarihi = Calendar.current.date(from: DateComponents(year: 1995, month: 1, day: 1)) ?? Date()

    @State private var isLoading = false
    @State private var alertMsg = ""
    @State private var showAlert = false
    @State private var wasSuccess = false

    @StateObject private var modeVoiceVM = RegisterModeVoiceManager()
    
    private var canSubmit: Bool {
        !ad.trimmingCharacters(in: .whitespaces).isEmpty &&
        !soyad.trimmingCharacters(in: .whitespaces).isEmpty &&
        tc.count == 11 &&
        tc.allSatisfy(\.isNumber) &&
        sifre.count == 4 &&
        sifre.allSatisfy(\.isNumber) &&
        !cinsiyet.isEmpty &&
        !isLoading
    }

    var body: some View {
        Group {
            if registerMode == nil {
                registerModeSelectionView
            } else if registerMode == .manual {
                manualRegisterView
            } else {
                voiceRegisterView
            }
        }
        .navigationTitle("Üye Ol")
        .alert("Bilgi", isPresented: $showAlert) {
            Button("Tamam") {
                if wasSuccess {
                    dismiss()
                }
            }
        } message: {
            Text(alertMsg)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Kapat") {
                    focused = nil
                }
            }
        }
    }
    private var registerModeSelectionView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "person.badge.plus")

            Text("Nasıl kayıt olmak istersiniz?")

            Button {
                registerMode = .manual
            } label: {
                Text("Manuel Kayıt")
            }

            Button {
                registerMode = .voice
                voiceRegisterVM.startVoiceRegister()
            } label: {
                Text("Sesli Kayıt")
            }

            Spacer()
        }
        .padding()

        // 👇 TAM BURAYA EKLE
        .onAppear {
            modeVoiceVM.onManualSelected = {
                registerMode = .manual
            }

            modeVoiceVM.onVoiceSelected = {
                registerMode = .voice
                voiceRegisterVM.startVoiceRegister()
            }

            modeVoiceVM.start()
        }
    }
    private var manualRegisterView: some View {
        ScrollView {
            VStack(spacing: 20) {
                SectionView(title: "Kimlik Bilgileri", color: Color(red: 0.22, green: 0.62, blue: 0.95)) {
                    TextField("Ad", text: $ad)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.givenName)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .ad)
                        .submitLabel(.next)
                        .onSubmit { focused = .soyad }

                    TextField("Soyad", text: $soyad)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.familyName)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .soyad)
                        .submitLabel(.next)
                        .onSubmit { focused = .tc }

                    TextField("T.C. Kimlik No", text: $tc)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .focused($focused, equals: .tc)
                        .onChange(of: tc) {
                            tc = String(tc.filter(\.isNumber).prefix(11))
                        }

                    DatePicker("Doğum Tarihi", selection: $dogumTarihi, displayedComponents: .date)
                        .padding(.vertical, 8)

                    Picker(selection: $cinsiyet) {
                        Text("Cinsiyet Seçin").tag("")
                        Text("Kadın").tag("Kadın")
                        Text("Erkek").tag("Erkek")
                    } label: {
                        HStack {
                            Text(cinsiyet.isEmpty ? "Cinsiyet Seçin" : cinsiyet)
                                .foregroundColor(.black)

                            Spacer()

                            Image(systemName: "chevron.down")
                                .foregroundColor(.gray)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding()
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                }

                SectionView(title: "Hesap Bilgileri", color: Color(red: 0.22, green: 0.62, blue: 0.95)) {
                    TextField("Dört Haneli PIN", text: $sifre)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .focused($focused, equals: .sifre)
                        .onChange(of: sifre) {
                            sifre = String(sifre.filter(\.isNumber).prefix(4))
                        }
                }

                Button {
                    Task { await submit() }
                } label: {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Kayıt Ol")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canSubmit ? Color.blue : Color.gray.opacity(0.45))
                .foregroundColor(.white)
                .font(.headline)
                .cornerRadius(18)
                .disabled(!canSubmit)
                .padding(.horizontal, 22)
            }
            .padding(.vertical, 10)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: focused == nil ? 0 : 70)
        }
    }

    private var voiceRegisterView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: voiceRegisterVM.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                .font(.system(size: 95))
                .foregroundColor(voiceRegisterVM.isRecording ? .red : .blue)

            Text(voiceRegisterVM.stepText)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if voiceRegisterVM.isListening {
                Text("Dinleniyor...")
                    .foregroundColor(.red)
                    .fontWeight(.semibold)
            }

            if voiceRegisterVM.isRecording {
                Text("Ses kaydı alınıyor...")
                    .foregroundColor(.red)
                    .fontWeight(.semibold)
            }

            Text("Alınan ses kaydı: \(voiceRegisterVM.sampleCount)/3")
                .font(.subheadline)
                .foregroundColor(.gray)

            Button {
                registerMode = nil
            } label: {
                Text("Geri")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .background(Color.gray.opacity(0.25), in: RoundedRectangle(cornerRadius: 16))
            .foregroundColor(.black)
            .padding(.horizontal, 30)

            Spacer()
        }
        .padding()
        .onAppear {
            voiceRegisterVM.onFinished = {
                wasSuccess = true
                alertMsg = "Sesli kayıt başarılı. Giriş yapabilirsiniz."
                showAlert = true
            }

            voiceRegisterVM.onError = { message in
                wasSuccess = false
                alertMsg = message
                showAlert = true
            }
        }
    }

    private func dateString(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    @MainActor
    private func submit() async {
        isLoading = true
        defer { isLoading = false }

        let payload = RegisterRequest(
            name: ad.trimmingCharacters(in: .whitespaces),
            surname: soyad.trimmingCharacters(in: .whitespaces),
            tcKimlik: tc,
            password: sifre,
            cinsiyet: cinsiyet,
            dogumTarihi: dateString(dogumTarihi)
        )

        do {
            let result = try await registerUser(payload)
            wasSuccess = true
            alertMsg = "\(result.message ?? "Kayıt başarılı"). Giriş yapabilirsiniz."
            showAlert = true
        } catch {
            wasSuccess = false
            alertMsg = error.localizedDescription
            showAlert = true
        }
    }

    private func registerUser(_ payload: RegisterRequest) async throws -> RegisterResponse {
        var request = URLRequest(url: APIConfig.registerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "API", code: -1, userInfo: [NSLocalizedDescriptionKey: "Sunucu cevabı okunamadı."])
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let msg = String(data: data, encoding: .utf8) ?? "Kayıt başarısız."
            throw NSError(domain: "API", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        return try JSONDecoder().decode(RegisterResponse.self, from: data)
    }
}

struct SectionView<Content: View>: View {
    let title: String
    let color: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.bold())
                .foregroundColor(.white)

            content
        }
        .padding(18)
        .background(color.gradient, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: color.opacity(0.25), radius: 10, x: 0, y: 6)
        .padding(.horizontal, 22)
    }
}

#Preview {
    NavigationStack {
        UyeOlView()
    }
}
