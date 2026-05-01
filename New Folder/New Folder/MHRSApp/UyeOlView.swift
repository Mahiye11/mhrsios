/*import SwiftUI
import Foundation

struct PatientCreate: Codable {
    let ad: String
    let soyad: String
    let tc_kimlik: String
    let sifre: String
    let email: String
    let dogum_tarihi: String
}

struct PatientDTO: Identifiable, Codable {
    let id: Int
    let ad: String
    let soyad: String
    let tc_kimlik: String
    let email: String
    let dogum_tarihi: String
    let created_at: String?
}


struct UyeOlView: View {
    @Environment(\.dismiss) private var dismiss

    enum Field: Hashable {
        case ad, soyad, tc, email, sifre
    }
    @FocusState private var focused: Field?

    @State private var ad = ""
    @State private var soyad = ""
    @State private var tc = ""
    @State private var email = ""
    @State private var sifre = ""
    @State private var dogumTarihi = Calendar.current.date(from: DateComponents(year: 1995, month: 1, day: 1)) ?? Date()

    @State private var isLoading = false
    @State private var alertMsg = ""
    @State private var showAlert = false
    @State private var wasSuccess = false

    private var canSubmit: Bool {
        !ad.trimmingCharacters(in: .whitespaces).isEmpty &&
        !soyad.trimmingCharacters(in: .whitespaces).isEmpty &&
        tc.count == 11 && tc.allSatisfy(\.isNumber) &&
        !email.isEmpty && !sifre.isEmpty &&
        !isLoading
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                SectionView(title: "Kimlik Bilgileri") {
                    TextField("Ad", text: $ad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textContentType(.givenName)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .ad)
                        .submitLabel(.next)
                        .onSubmit { focused = .soyad }

                    TextField("Soyad", text: $soyad)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textContentType(.familyName)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .soyad)
                        .submitLabel(.next)
                        .onSubmit { focused = .tc }

                    TextField("T.C. Kimlik (11 hane)", text: $tc)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.numberPad)
                        .onChange(of: tc) {
                            tc = String(tc.filter(\.isNumber).prefix(11))
                        }
                        .focused($focused, equals: .tc)
                        .submitLabel(.next)
                        .onSubmit { focused = .email }
                    
                    DatePicker("Doğum Tarihi", selection: $dogumTarihi, displayedComponents: .date)
                        .padding(.vertical, 8)
                }

                SectionView(title: "Hesap Bilgileri") {
                    TextField("E-posta", text: $email)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .focused($focused, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focused = .sifre }

                    SecureField("Şifre", text: $sifre)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textContentType(.newPassword)
                        .focused($focused, equals: .sifre)
                        .submitLabel(.done)
                        .onSubmit { focused = nil }
                }

                Button {
                    Task { await submit() }
                } label: {
                    if isLoading { ProgressView().tint(.white) }
                    else { Text("Kayıt Ol").fontWeight(.semibold) }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(14)
                .disabled(!canSubmit)
                .padding(.horizontal, 20)
            }
            .padding(.vertical, 10)
        }
        .navigationTitle("Üye Ol")
        .alert("Bilgi", isPresented: $showAlert) {
            Button("Tamam") {
                if wasSuccess { dismiss() }
            }
        } message: {
            Text(alertMsg)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Kapat") { focused = nil }
            }
        }
        .safeAreaInset(edge: .bottom) {
             Color.clear.frame(height: focused == nil ? 0 : 70)
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

        let payload = PatientCreate(
            ad: ad.trimmingCharacters(in: .whitespaces),
            soyad: soyad.trimmingCharacters(in: .whitespaces),
            tc_kimlik: tc,
            sifre: sifre,
            email: email.lowercased(),
            dogum_tarihi: dateString(dogumTarihi)
        )

        do {
            let dto = try await API.register(payload)
            wasSuccess = true
            alertMsg = "Kayıt oluşturuldu. ID: \(dto.id)"
            showAlert = true
        } catch let apiErr as API.Failure {
            wasSuccess = false
            switch apiErr {
            case .invalidResponse(let code):
                if code == 409 { alertMsg = "Bu T.C. veya e-posta ile zaten kayıt var." }
                else if code == 422 { alertMsg = "Eksik veya hatalı alanlar var." }
                else { alertMsg = "Sunucu hatası: \(code)" }
            case .decoding(let err):
                alertMsg = "Veri çözümleme hatası: \(err.localizedDescription)"
            }
            showAlert = true
        } catch {
            wasSuccess = false
            alertMsg = error.localizedDescription
            showAlert = true
        }
    }
}

struct SectionView<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal, 20)
    }
}
*/
