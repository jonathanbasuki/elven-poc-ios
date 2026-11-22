import Foundation

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case httpError(Int, Data?)
    case decodingError(Error, Data?)
    case serverError(code: String, message: String)
}

class APIClient {
    static let shared = APIClient()
    private let session = URLSession.shared

    private func request<T: Decodable>(_ endpoint: String, method: String = "GET", body: Data? = nil, logRaw: Bool = false) async throws -> T {
        guard let url = URL(string: "\(APIConfig.baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = APIConfig.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        if logRaw, let json = String(data: data, encoding: .utf8) {
            print("📦 Raw API response (\(endpoint)): \(json)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to parse server error format: {"error": {"code": ..., "message": ...}}
            if let serverError = try? JSONDecoder().decode(ServerError.self, from: data) {
                throw APIError.serverError(code: serverError.error.code, message: serverError.error.message)
            }
            throw APIError.httpError(httpResponse.statusCode, data)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error, data)
        }
    }

    // MARK: - Auth
    func login(email: String, password: String) async throws -> TokenResponse {
        let body = try JSONEncoder().encode(["email": email, "password": password])
        return try await request("/api/v1/auth/login", method: "POST", body: body)
    }

    // MARK: - Zones
    func getZones() async throws -> [ZoneResponse] {
        return try await request("/api/v1/zones")
    }

    // MARK: - Tasks
    func getTasks() async throws -> [TaskResponse] {
        return try await request("/api/v1/tasks")
    }

    func getFootage(taskId: UUID) async throws -> FootageResponse {
        return try await request("/api/v1/tasks/\(taskId)/footage")
    }

    // MARK: - Crowd
    func getCrowd(zoneId: String) async throws -> CrowdOut {
        return try await request("/api/v1/zones/\(zoneId)/crowd")
    }

    func getCrowdHistory(zoneId: String, limit: Int = 12) async throws -> [HistoryBucketOut] {
        return try await request("/api/v1/zones/\(zoneId)/crowd/history?limit=\(limit)")
    }
}
