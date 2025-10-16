import SwiftUI
import Foundation

@MainActor
final class LoginViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var error: String?

    
    @AppStorage("user_id") private var userId: Int = 0
    @AppStorage("user_name") private var userName: String = ""

    func login(tc: String, password: String) async -> Bool {
        error = nil

        
        guard Self.isValidTCKN(tc) else {
            error = "TC Kimlik numarası 11 haneli olmalı."
            return false
        }
        guard !password.isEmpty else {
            error = "Şifre boş olamaz."
            return false
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let resp = try await API.login(tc: tc, password: password)
        
            userId = resp.user_id
            userName = "\(resp.ad) \(resp.soyad)"
            return true
        } catch {
            self.error = (error as NSError).localizedDescription
            return false
        }
    }

    private static func isValidTCKN(_ s: String) -> Bool {
        let digits = s.trimmingCharacters(in: .whitespaces)
        let re = try! NSRegularExpression(pattern: #"^\d{11}$"#)
        return re.firstMatch(in: digits, range: NSRange(location: 0, length: digits.utf16.count)) != nil
    }
}
