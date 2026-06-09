import Foundation

enum APIConfig {
    static let baseURL = "http://192.168.1.158:8080"
    static let pythonBaseURL = "http://192.168.1.158:5836"

    static var symptomAnalyzeURL: URL {
        URL(string: "\(pythonBaseURL)/predict")!
    }

    static var aiRecommendationURL: URL {
        URL(string: "\(baseURL)/api/ai/recommend-doctors")!
    }

    static var loginURL: URL {
        URL(string: "\(baseURL)/api/users/login")!
    }

    static var recognizeTcURL: URL {
        URL(string: "\(baseURL)/api/users/recognize-tc")!
    }

    static var voiceLoginURL: URL {
        URL(string: "\(baseURL)/api/users/login-voice")!
    }

    static var registerURL: URL {
        URL(string: "\(baseURL)/api/users/register")!
    }

    static func userDetailURL(userId: Int) -> URL {
        URL(string: "\(baseURL)/api/users/\(userId)")!
    }

    static var registerVoiceURL: URL {
        URL(string: "\(baseURL)/api/users/register-voice")!
    }

    static func appointmentsByUserURL(userId: Int) -> URL {
        URL(string: "\(baseURL)/api/appointments/user/\(userId)")!
    }

    static func deleteAppointmentURL(appointmentId: Int) -> URL {
        URL(string: "\(baseURL)/api/appointments/\(appointmentId)")!
    }

    static var createAppointmentURL: URL {
        URL(string: "\(baseURL)/api/appointments")!
    }

    static var createFamilyAppointmentURL: URL {
        URL(string: "\(baseURL)/api/appointments")!
    }

    static func availableSlotsURL(doctorId: Int, date: String) -> URL {
        URL(string: "\(baseURL)/api/appointments/available-slots?doctorId=\(doctorId)&date=\(date)")!
    }

    static func familyDoctorURL(userId: Int) -> URL {
        URL(string: "\(baseURL)/api/family-doctor/\(userId)")!
    }
}
