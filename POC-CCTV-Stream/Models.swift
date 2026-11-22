import Foundation

// MARK: - User
struct UserResponse: Codable {
    let id: UUID
    let email: String
    let fullName: String
    let role: String
    let isActive: Bool
}

// MARK: - Token
struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    let user: UserResponse
}

// MARK: - Zone
struct ZoneResponse: Codable, Identifiable, Hashable {
    var id: String { zoneId }
    let zoneId: String
    let name: String
    let threshold: Int
    let isActiveTask: Bool
    let cameraId: String?
    let idleStaff: [IdleStaffOut]?

    enum CodingKeys: String, CodingKey {
        case zoneId
        case name
        case threshold
        case isActiveTask
        case cameraId
        case idleStaff
    }
}

struct IdleStaffOut: Codable, Hashable {
    let staffId: UUID
    let fullName: String
}

// MARK: - Camera (obtained via zones; no dedicated GET /cameras endpoint for iOS)
struct CameraResponse: Codable, Identifiable, Hashable {
    var id: String { cameraId }
    let cameraId: String
    let name: String?
    let rtspUrl: String?
    let isActive: Bool?

    var displayName: String { name ?? cameraId }
}

// MARK: - Task
struct TaskResponse: Codable, Identifiable, Hashable {
    var id: UUID { taskId }
    let taskId: UUID
    let zoneId: String
    let status: String
    let totalStaff: Int
    let instruction: String
    let expiresAt: String
    let acceptedCount: Int
    let completedCount: Int
    let acceptedStaff: [AcceptedStaffOut]
}

struct AcceptedStaffOut: Codable, Hashable {
    let staffId: UUID
    let name: String
    let status: String
    let completedAt: String?
}

// MARK: - Footage
struct FootageResponse: Codable {
    let taskId: UUID
    let status: String
    let url: String?
    let error: String?
}

// MARK: - Server Error
struct ServerError: Codable {
    let error: ServerErrorDetail
}

struct ServerErrorDetail: Codable {
    let code: String
    let message: String
}

// MARK: - Crowd
struct CrowdOut: Codable {
    let zoneId: String
    let count: Int
    let status: String
    let observedAt: String?
}

// MARK: - History Bucket
struct HistoryBucketOut: Codable {
    let bucketStart: String
    let avgCount: Double
    let peakCount: Int
}
