import SwiftUI

// MARK: - DTO

struct UserProfileDTO: Codable {
    let id: Int?
    let name: String?
    let surname: String?
    let tcKimlik: String?
    var phone: String?
    let cinsiyet: String?
    let dogumTarihi: String?
    var password: String?
}

// MARK: - Profile View

struct ProfilView: View {
    let userId: Int
    let fallbackName: String
    let userTc: String

    @Environment(\.dismiss) private var dismiss

    @State private var user: UserProfileDTO?

    @State private var name = ""
    @State private var surname = ""
    @State private var tcKimlik = ""
    @State private var phone = ""
    @State private var cinsiyet = ""
    @State private var dogumTarihi = ""
    @State private var password = ""

    @State private var showPassword = false
    @State private var isLoading = false
    @State private var alertMessage = ""
    @State private var showAlert = false

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {

                    headerView

                    profileCard

                    editCard

                    saveButton

                    cancelButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 30)
            }
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

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2.bold())
                    .foregroundColor(.blue)
            }

            Text("Profilim")
                .font(.largeTitle.bold())
                .foregroundColor(.primary)

            Spacer()
        }
    }

    // MARK: - Profile Card

    private var profileCard: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 82, height: 82)

                Image(systemName: "person.fill")
                    .font(.system(size: 38))
                    .foregroundColor(.blue)
            }

            Text(fullName)
                .font(.title2.bold())
                .foregroundColor(.primary)

            Divider()

            ProfileInfoRow(
                icon: "person.fill",
                title: "Ad",
                value: name.isEmpty ? "Ad bilgisi yok" : name
            )

            ProfileInfoRow(
                icon: "person.fill",
                title: "Soyad",
                value: surname.isEmpty ? "Soyad bilgisi yok" : surname
            )

            ProfileInfoRow(
                icon: "person.text.rectangle.fill",
                title: "TC Kimlik No",
                value: maskedTC
            )

            ProfileInfoRow(
                icon: "phone.fill",
                title: "Telefon Numarası",
                value: phone.isEmpty ? "Telefon bilgisi yok" : phone
            )

            ProfileInfoRow(
                icon: "person.2.fill",
                title: "Cinsiyet",
                value: cinsiyet.isEmpty ? "Cinsiyet bilgisi yok" : cinsiyet
            )

            ProfileInfoRow(
                icon: "calendar",
                title: "Doğum Tarihi",
                value: dogumTarihi.isEmpty ? "Doğum tarihi bilgisi yok" : dogumTarihi
            )
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    // MARK: - Edit Card

    private var editCard: some View {
        VStack(spacing: 14) {
            ProfileEditField(
                title: "Telefon Numarası",
                icon: "phone.fill",
                text: $phone,
                keyboard: .phonePad,
                readOnly: false
            )

            HStack {
                Image(systemName: "lock.fill")
                    .foregroundColor(.blue)
                    .frame(width: 24)

                if showPassword {
                    TextField("Yeni Şifre (isteğe bağlı)", text: $password)
                        .keyboardType(.numberPad)
                } else {
                    SecureField("Yeni Şifre (isteğe bağlı)", text: $password)
                        .keyboardType(.numberPad)
                }

                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(.gray)
                }
            }
            .padding()
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.blue.opacity(0.45), lineWidth: 1.3)
            )
            .cornerRadius(16)
            .onChange(of: password) {
                password = String(password.filter(\.isNumber).prefix(4))
            }
        }
        .padding(18)
        .background(Color.white)
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }

    // MARK: - Buttons

    private var saveButton: some View {
        Button {
            Task {
                await updateProfile()
            }
        } label: {
            HStack {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Kaydet")
                        .font(.headline.bold())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(
                    colors: [Color.blue, Color.red.opacity(0.85)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(22)
        }
        .disabled(isLoading)
    }

    private var cancelButton: some View {
        Button {
            dismiss()
        } label: {
            Text("İptal")
                .font(.headline.bold())
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .foregroundColor(.red)
                .background(Color.white)
                .cornerRadius(22)
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.red.opacity(0.45), lineWidth: 1.2)
                )
        }
    }

    // MARK: - Computed

    private var fullName: String {
        let combined = "\(name) \(surname)".trimmingCharacters(in: .whitespaces)
        return combined.isEmpty ? fallbackName : combined
    }

    private var maskedTC: String {
        let tc = tcKimlik.isEmpty ? userTc : tcKimlik

        guard tc.count == 11 else {
            return "***********"
        }

        let first = tc.prefix(2)
        let last = tc.suffix(2)

        return "\(first)*******\(last)"
    }

    // MARK: - API

    @MainActor
    private func fetchUser() async {
        isLoading = true
        defer { isLoading = false }

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

            let decoded = try JSONDecoder().decode(UserProfileDTO.self, from: data)
            self.user = decoded

            self.name = decoded.name ?? ""
            self.surname = decoded.surname ?? ""
            self.tcKimlik = decoded.tcKimlik ?? userTc
            self.phone = decoded.phone ?? ""
            self.cinsiyet = decoded.cinsiyet ?? ""
            self.dogumTarihi = decoded.dogumTarihi ?? ""

        } catch {
            alertMessage = "Profil bağlantı hatası: \(error.localizedDescription)"
            showAlert = true
        }
    }

    @MainActor
    private func updateProfile() async {
        guard var currentUser = user else {
            alertMessage = "Kullanıcı bilgisi bulunamadı."
            showAlert = true
            return
        }

        if !password.isEmpty && password.count != 4 {
            alertMessage = "Yeni şifre 4 haneli olmalıdır."
            showAlert = true
            return
        }

        isLoading = true
        defer { isLoading = false }

        currentUser.phone = phone

        if !password.isEmpty {
            currentUser.password = password
        }

        do {
            var request = URLRequest(url: APIConfig.userDetailURL(userId: userId))
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            request.httpBody = try JSONEncoder().encode(currentUser)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                alertMessage = "Sunucu cevabı alınamadı."
                showAlert = true
                return
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                alertMessage = String(data: data, encoding: .utf8) ?? "Profil güncellenemedi."
                showAlert = true
                return
            }

            if let updated = try? JSONDecoder().decode(UserProfileDTO.self, from: data) {
                self.user = updated
                self.phone = updated.phone ?? phone
            }

            password = ""
            alertMessage = "Profil başarıyla güncellendi."
            showAlert = true

        } catch {
            alertMessage = "Profil güncelleme hatası: \(error.localizedDescription)"
            showAlert = true
        }
    }
}

// MARK: - Info Row

struct ProfileInfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.10))
                    .frame(width: 36, height: 36)

                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.blue)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.gray)

                Text(value)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Edit Field

struct ProfileEditField: View {
    let title: String
    let icon: String
    @Binding var text: String
    let keyboard: UIKeyboardType
    let readOnly: Bool

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)

            TextField(title, text: $text)
                .keyboardType(keyboard)
                .disabled(readOnly)
        }
        .padding()
        .background(readOnly ? Color.gray.opacity(0.08) : Color.white)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.blue.opacity(0.45), lineWidth: 1.3)
        )
        .cornerRadius(16)
    }
}
