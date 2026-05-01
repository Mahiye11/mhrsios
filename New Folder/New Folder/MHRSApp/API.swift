import Foundation

enum APIConfig {
    static let baseURL = "http://192.168.1.158:5050"
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
}
/*import Foundation

enum APIConfig {
    static let host = "192.168.1.158"
    static let usersPort = 5061
    static let hospitalsPort = 5061
    static let timeout: TimeInterval = 30
    static let prefix = "/api/v0"

    static var baseURL: String {
        "http://\(host):\(usersPort)"
    }

    static var voiceAnalyzeURL: URL {
        URL(string: "\(baseURL)/analyze")!
    }
}
enum API {
    enum Failure: Error { case invalidResponse(Int), decoding(Error) }

    private static func makeURL(port: Int, path: String, query: [URLQueryItem]? = nil) -> URL {
        var c = URLComponents()
        c.scheme = "http"
        c.host   = APIConfig.host
        c.port   = port
        c.path   = APIConfig.prefix + path
        c.queryItems = query
        return c.url!
    }

    private static var session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest  = APIConfig.timeout
        cfg.timeoutIntervalForResource = APIConfig.timeout
        return URLSession(configuration: cfg)
    }()

    private static func jsonDecoder() -> JSONDecoder {
        let dec = JSONDecoder()
        return dec
    }

    private static func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            if let m = try? JSONDecoder().decode([String:String].self, from: data),
               let detail = m["detail"] {
                throw NSError(domain: "API", code: code,
                              userInfo: [NSLocalizedDescriptionKey: detail])
            }
            throw Failure.invalidResponse(code)
        }
        do { return try jsonDecoder().decode(T.self, from: data) }
        catch { throw Failure.decoding(error) }
    }

    private static func get<T: Decodable>(_ url: URL) async throws -> T {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        return try await send(req)
    }

    private static func postJSON<T: Decodable, B: Encodable>(_ url: URL, body: B) async throws -> T {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        return try await send(req)
    }

    static func cities() async throws -> [IlDTO] {
        try await get(makeURL(port: APIConfig.hospitalsPort, path: "/iller"))
    }

    static func districts(il: IlDTO) async throws -> [IlceDTO] {
        try await get(makeURL(
            port: APIConfig.hospitalsPort,
            path: "/ilceler",
            query: [URLQueryItem(name: "il_id", value: String(il.id))]
        ))
    }

    static func hospitals(ilce: IlceDTO) async throws -> [HastaneDTO] {
        try await get(makeURL(
            port: APIConfig.hospitalsPort,
            path: "/hastaneler",
            query: [URLQueryItem(name: "ilce_id", value: String(ilce.id))]
        ))
    }

    static func doctors(hastane: HastaneDTO) async throws -> [DoctorDTO] {
        try await get(makeURL(
            port: APIConfig.hospitalsPort,
            path: "/doktorlar",
            query: [URLQueryItem(name: "hastane_id", value: String(hastane.id))]
        ))
    }

    struct LoginRequest: Encodable { let tc_kimlik: String; let sifre: String }
    struct LoginResponse: Decodable {
        let message: String
        let user_id: Int
        let ad: String
        let soyad: String
        let email: String
    }

    static func login(tc: String, password: String) async throws -> LoginResponse {
        try await postJSON(
            makeURL(port: APIConfig.usersPort, path: "/hastakayit/login"),
            body: LoginRequest(tc_kimlik: tc, sifre: password)
        )
    }

    static func register(_ payload: PatientCreate) async throws -> PatientDTO {
        try await postJSON(
            makeURL(port: APIConfig.usersPort, path: "/hastakayit"),
            body: payload
        )
    }
}
*/
