import Foundation
import Combine

class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var isAuthenticated = false

    init() {
        if APIConfig.authToken != nil {
            self.isAuthenticated = true
        }
    }

    func login(email: String, password: String) async throws {
        let response = try await APIClient.shared.login(email: email, password: password)
        APIConfig.authToken = response.accessToken
        self.isAuthenticated = true
    }

    func logout() {
        APIConfig.authToken = nil
        self.isAuthenticated = false
    }

    func handleUnauthenticated() {
        logout()
    }
}
