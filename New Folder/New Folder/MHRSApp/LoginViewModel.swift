import Foundation

struct LoginResponse: Codable {
    let message: String?
    let userId: Int?
    let name: String?
    let tcKimlik: String?
    let authMethod: String?
    let hasVoiceRecord: Bool?
}

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var error: String?
    @Published var userName: String?
    @Published var userId: Int?

    func login(tc: String, password: String) async -> Bool {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            var request = URLRequest(url: APIConfig.loginURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body: [String: String] = [
                "tcKimlik": tc,
                "password": password
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                error = "Sunucu cevabı okunamadı."
                return false
            }

            guard 200..<300 ~= httpResponse.statusCode else {
                let message = String(data: data, encoding: .utf8) ?? "Giriş başarısız."
                error = message
                return false
            }

            let result = try JSONDecoder().decode(LoginResponse.self, from: data)
            self.userId = result.userId
            self.userName = result.name

            return true

        } catch {
            self.error = "Bağlantı hatası: \(error.localizedDescription)"
            return false
        }
    }
}
