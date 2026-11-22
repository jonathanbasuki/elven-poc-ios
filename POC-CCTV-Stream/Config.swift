import Foundation

struct APIConfig {
    static let baseURL = "http://192.168.0.101:8080"
    static var authToken: String? {
        get { UserDefaults.standard.string(forKey: "auth_token") }
        set { UserDefaults.standard.set(newValue, forKey: "auth_token") }
    }
}

struct MediaMTXConfig {
    static let host = "192.168.0.101"
    static let port = 8888
    static var hlsURL: String {
        "http://\(host):\(port)"
    }
}
