import SwiftUI

struct UserProfileDTO: Codable {
    let id: Int?
    let name: String?
    let surname: String?
    let tcKimlik: String?
}
struct ProfilView: View {
    let userId: Int
    let fallbackName: String
    let userTc: String

    @Environment(\.dismiss) private var dismiss

    @State private var user: UserProfileDTO?
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var isLoading = false
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {

                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .foregroundColor(.black)
                    }

                    Text("Profilim")
                        .font(.largeTitle.bold())

                    Spacer()
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Ad Soyad")
                        .font(.caption)
                        .foregroundColor(.gray)

                    Text(fullName.isEmpty ? "Bilgi alınamadı" : fullName)
                        .font(.title3.bold())
                        .foregroundColor(.black)

                    Text("T.C. Kimlik No")
                        .font(.caption)
                        .foregroundColor(.gray)

                    Text(maskedTC)
                        .font(.title3.bold())
                        .foregroundColor(.black)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))

                VStack(spacing: 14) {
                    SecureField("Mevcut Şifre", text: $currentPassword)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)

                    SecureField("Yeni Şifre", text: $newPassword)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .onChange(of: newPassword) {
                            newPassword = String(newPassword.filter(\.isNumber).prefix(4))
                        }

                    Button {
                        Task {
                            await changePassword()
                        }
                    } label: {
                        if isLoading {
                            ProgressView().tint(.white)
                        } else {
                            Text("Şifreyi Güncelle")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 14))
                    .foregroundColor(.white)
                    .disabled(currentPassword.isEmpty || newPassword.count != 4 || isLoading)
                }
                .padding()
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)

                Spacer()
            }
            .padding(24)
        }
        .navigationBarBackButtonHidden(true)
        .task {
            await fetchUser()
        }
        .alert("Bilgi", isPresented: $showAlert) {
            Button("Tamam") {}
        } message: {
            Text(alertMessage)
        }
    }

    private var fullName: String {
        let name = user?.name ?? ""
        let surname = user?.surname ?? ""
        let combined = "\(name) \(surname)".trimmingCharacters(in: .whitespaces)

        return combined.isEmpty ? fallbackName : combined
    }

    private var maskedTC: String {
        let tc = user?.tcKimlik ?? userTc

        guard tc.count == 11 else {
            return "***********"
        }

        let first = tc.prefix(2)
        let last = tc.suffix(2)

        return "\(first)*******\(last)"
    }

    @MainActor
    private func fetchUser() async {
        do {
            let (data, response) = try await URLSession.shared.data(
                from: APIConfig.userDetailURL(userId: userId)
            )

            guard let httpResponse = response as? HTTPURLResponse else {
                alertMessage = "Sunucu cevabı yok."
                showAlert = true
                return
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                alertMessage = String(data: data, encoding: .utf8) ?? "Profil bilgileri alınamadı."
                showAlert = true
                return
            }

            self.user = try JSONDecoder().decode(UserProfileDTO.self, from: data)

        } catch {
            alertMessage = "Profil bağlantı hatası: \(error.localizedDescription)"
            showAlert = true
        }
    }

    @MainActor
    private func changePassword() async {
        guard !currentPassword.isEmpty else {
            alertMessage = "Mevcut şifreyi giriniz."
            showAlert = true
            return
        }

        guard newPassword.count == 4 else {
            alertMessage = "Yeni şifre 4 haneli olmalıdır."
            showAlert = true
            return
        }

        alertMessage = "Şifre güncelleme özelliği daha sonra aktif edilecek."
        showAlert = true

        currentPassword = ""
        newPassword = ""
    }
}
