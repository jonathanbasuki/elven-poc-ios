# iOS POC: Local CCTV Live & Recorded Footage Integration Guide

This guide provides step-by-step instructions for an AI agent to build an iOS proof-of-concept (POC) app that integrates:
- **Live CCTV streaming** via MediaMTX HLS
- **Recorded footage playback** via local HLS segments

---

## 1. Architecture Overview

```
┌─────────────┐     RTSP      ┌──────────────┐     HLS      ┌──────────────────┐
│   Camera    │ ────────────► │   MediaMTX   │ ───────────► │ recordings/      │
└─────────────┘               │  (Docker)    │   segments   │  footage/        │
                              └──────┬───────┘              │  {taskId}/       │
                                     │                      │  playlist.m3u8   │
                      Live HLS      │                      │  segment_*.ts    │
                                     ▼                      └────────┬─────────┘
                              ┌──────────────┐                    │
                              │   API Server │                    │
                              │  (FastAPI)   │◄───────────────────┘
                              └──────┬───────┘
                                     │
                    Live HLS         │                    Recorded HLS
                                     ▼                             
                              ┌──────────────────┐
                              │   iOS POC App    │
                              │  (AVPlayer)      │
                              └──────────────────┘
```

---

## 2. Prerequisites

### Server-Side (Already Implemented)
- ✅ MediaMTX running with HLS enabled (`make mediamtx`)
- ✅ API server with footage endpoints (`make api`)
- ✅ CCTV workers for detection (`make cctv-all`)
- ✅ Database with cameras, zones, tasks

### iOS Development Environment
- Xcode 15+
- iOS 16+ deployment target
- Swift 5.9+
- Network access to server (LAN)

---

## 3. iOS Project Setup

### 3.1 Create Xcode Project
```
File → New → Project → iOS → App
- Product Name: PlongPOC
- Interface: SwiftUI
- Language: Swift
- Minimum Deployment: iOS 16.0
```

### 3.2 Add Required Capabilities
In `PlongPOC.entitlements` or Signing & Capabilities:
```
- Network → Outgoing Connections (Client)
- App Transport Security → Allow Arbitrary Loads (for local HTTP)
```

### 3.3 Info.plist - App Transport Security
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
    <key>NSExceptionDomains</key>
    <dict>
        <key>localhost</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
        </dict>
    </dict>
</dict>
```

---

## 4. Network Layer

### 4.1 API Configuration
```swift
// Config.swift
struct APIConfig {
    static let baseURL = "http://192.168.1.100:8080"  // Change to your server IP
    static let wsBaseURL = "ws://192.168.1.100:8080"
    
    static var authToken: String? {
        get { UserDefaults.standard.string(forKey: "auth_token") }
        set { UserDefaults.standard.set(newValue, forKey: "auth_token") }
    }
}
```

### 4.2 API Client with Auth
```swift
// APIClient.swift
import Foundation

class APIClient {
    static let shared = APIClient()
    private let session = URLSession.shared
    private let baseURL = APIConfig.baseURL
    
    private var authHeaders: [String: String] {
        guard let token = APIConfig.authToken else { return [:] }
        return ["Authorization": "Bearer \(token)"]
    }
    
    func request<T: Decodable>(_ endpoint: String, method: String = "GET", body: Data? = nil) async throws -> T {
        let url = URL(string: "\(baseURL)\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.allHTTPHeaderFields = authHeaders
        request.httpBody = body
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode, data)
        }
        
        return try JSONDecoder().decode(T.self, from: data)
    }
    
    // Convenience methods
    func login(email: String, password: String) async throws -> TokenResponse {
        let body = ["email": email, "password": password]
        let data = try JSONEncoder().encode(body)
        return try await request("/api/v1/auth/login", method: "POST", body: data)
    }
    
    func getFootage(taskId: UUID) async throws -> FootageResponse {
        return try await request("/api/v1/tasks/\(taskId)/footage")
    }
    
    func getLiveCrowd(zoneId: String) async throws -> LiveCrowdResponse {
        return try await request("/api/v1/zones/\(zoneId)/crowd")
    }
    
    func getZones() async throws -> [ZoneResponse] {
        return try await request("/api/v1/zones")
    }
}

enum APIError: Error {
    case invalidResponse
    case httpError(Int, Data)
}

struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: UserResponse
}
```

---

## 5. Authentication Flow

### 5.1 Login View
```swift
// LoginView.swift
import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var error: String?
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Plong POC")
                    .font(.largeTitle)
                    .bold()
                
                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                    
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                }
                
                if let error = error {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                Button(action: login) {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Sign In")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || email.isEmpty || password.isEmpty)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Sign In")
        }
    }
    
    private func login() {
        isLoading = true
        error = nil
        
        Task {
            do {
                try await AuthManager.shared.login(email: email, password: password)
                await MainActor.run { isLoading = false }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}
```

### 5.2 Auth Manager
```swift
// AuthManager.swift
import Foundation
import Combine

class AuthManager: ObservableObject {
    static let shared = AuthManager()
    
    @Published var isAuthenticated = false
    @Published var currentUser: UserResponse?
    
    private init() {
        // Check for existing token on launch
        if APIConfig.authToken != nil {
            Task { await validateToken() }
        }
    }
    
    func login(email: String, password: String) async throws {
        let response = try await APIClient.shared.login(email: email, password: password)
        APIConfig.authToken = response.accessToken
        self.currentUser = response.user
        self.isAuthenticated = true
    }
    
    func logout() {
        APIConfig.authToken = nil
        self.currentUser = nil
        self.isAuthenticated = false
    }
    
    private func validateToken() async {
        do {
            _ = try await APIClient.shared.getZones()
            self.isAuthenticated = true
        } catch {
            logout()
        }
    }
}
```

---

## 6. Live CCTV Streaming

### 6.1 Live Stream Service
```swift
// LiveStreamService.swift
import AVFoundation
import Combine

class LiveStreamService: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var error: String?
    
    private var currentCameraId: String?
    private var authToken: String?
    
    func startLiveStream(cameraId: String, token: String) {
        self.currentCameraId = cameraId
        self.authToken = token
        
        // MediaMTX HLS endpoint for live stream
        let streamURL = "\(APIConfig.baseURL)/api/v1/cameras/\(cameraId)/stream"
        
        guard let url = URL(string: streamURL) else {
            self.error = "Invalid stream URL"
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let asset = AVURLAsset(url: URL(string: "\(APIConfig.baseURL)/api/v1/cameras/\(cameraId)/stream")!)
        
        // Add auth for HLS playlist + segments
        let delegate = AuthResourceLoaderDelegate(token: token)
        asset.resourceLoader.setDelegate(delegate, queue: .main)
        
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        
        self.player = player
        player.play()
        self.isPlaying = true
    }
    
    func stop() {
        player?.pause()
        player = nil
        isPlaying = false
        currentCameraId = nil
    }
}

// Reuse AuthResourceLoaderDelegate from earlier
```

---

## 6. Recorded Footage Playback

### 6.1 Footage Player View
```swift
// FootagePlayerView.swift
import SwiftUI
import AVKit

struct FootagePlayerView: View {
    let taskId: UUID
    @StateObject private var viewModel = FootagePlayerViewModel()
    @EnvironmentObject var authManager: AuthManager
    
    var body: some View {
        VStack {
            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .onAppear { viewModel.play() }
                    .onDisappear { viewModel.stop() }
            } else if viewModel.isLoading {
                ProgressView("Loading footage...")
            } else if let error = viewModel.error {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text(error)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("Retry") { viewModel.loadFootage() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Footage Playback")
        .task {
            await viewModel.loadFootage(taskId: taskId, token: authManager.currentUser?.accessToken ?? "")
        }
    }
}

@MainActor
class FootagePlayerViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isLoading = false
    @Published var error: String?
    @Published var footageInfo: FootageResponse?
    
    private var currentTaskId: UUID?
    
    func loadFootage(taskId: UUID, token: String) async {
        isLoading = true
        error = nil
        currentTaskId = taskId
        
        do {
            let footage = try await APIClient.shared.getFootage(taskId: taskId)
            footageInfo = footage
            
            guard footage.status == "ready", let streamPath = footage.url else {
                throw FootageError.notReady(footage.status)
            }
            
            let streamURL = "\(APIConfig.baseURL)\(streamPath)"
            await setupPlayer(streamURL: streamURL, token: "")
            
        } catch {
            error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func setupPlayer(streamURL: String, token: String) async {
        guard let url = URL(string: streamURL) else {
            error = "Invalid stream URL"
            return
        }
        
        let asset = AVURLAsset(url: url)
        let delegate = AuthResourceLoaderDelegate(token: "")
        asset.resourceLoader.setDelegate(delegate, queue: .main)
        
        let playerItem = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: playerItem)
        
        self.player = player
        player.play()
    }
    
    func stop() {
        player?.pause()
        player = nil
    }
}
```

---

## 7. Camera & Zone Selection UI

### 7.1 Main Dashboard
```swift
// ContentView.swift
struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var zoneVM = ZoneViewModel()
    @StateObject private var cameraVM = CameraViewModel()
    
    @State private var selectedZone: ZoneResponse?
    @State private var selectedCamera: CameraResponse?
    @State private var showingLive = false
    @State private var showingFootage = false
    @State private var selectedTask: TaskResponse?
    
    var body: some View {
        NavigationView {
            SidebarView(
                zones: zoneVM.zones,
                cameras: cameraVM.cameras,
                selectedZone: $selectedZone,
                selectedCamera: $selectedCamera,
                onLiveTap: { camera in
                    selectedCamera = camera
                    showingLive = true
                },
                onFootageTap: { task in
                    selectedTask = task
                    showingFootage = true
                }
            )
            
            DetailView(
                selectedZone: selectedZone,
                selectedCamera: selectedCamera,
                showingLive: $showingLive,
                showingFootage: $showingFootage,
                selectedTask: selectedTask
            )
        }
        .task {
            await zoneVM.load()
            await cameraVM.load()
        }
    }
}
```

### 7.2 Zone & Camera ViewModels
```swift
// ZoneViewModel.swift
class ZoneViewModel: ObservableObject {
    @Published var zones: [ZoneResponse] = []
    
    func load() async {
        do {
            zones = try await APIClient.shared.getZones()
        } catch {
            print("Failed to load zones: \(error)")
        }
    }
}

// CameraViewModel.swift
class CameraViewModel: ObservableObject {
    @Published var cameras: [CameraResponse] = []
    
    func load() async {
        do {
            cameras = try await APIClient.shared.getCameras()
        } catch {
            print("Failed to load cameras: \(error)")
        }
    }
}
```

---

## 8. Real-time Crowd Data (WebSocket)

### 8.1 Crowd WebSocket Service
```swift
// CrowdWebSocketService.swift
import Foundation
import Combine

class CrowdWebSocketService: ObservableObject {
    @Published var liveCounts: [String: Int] = [:]  // zoneId -> count
    @Published var isConnected = false
    
    private var webSocketTask: URLSessionWebSocketTask?
    private var reconnectTimer: Timer?
    
    func connect(zoneId: String, token: String) {
        let wsURL = "\(APIConfig.wsBaseURL)/api/v1/crowd/live?ticket=\(token)"
        guard let url = URL(string: wsURL) else { return }
        
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveMessage()
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                if case .string(let text) = message {
                    self?.handleMessage(text)
                }
                self?.receiveMessage()
            case .failure(let error):
                print("WebSocket error: \(error)")
                self?.scheduleReconnect()
            }
        }
    }
    
    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cameraId = json["cameraId"] as? String,
              let counts = json["counts"] as? [String: Int] else { return }
        
        DispatchQueue.main.async {
            for (zoneId, count) in counts {
                self.liveCounts[zoneId] = count
            }
        }
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        reconnectTimer?.invalidate()
    }
}
```

---

## 9. Complete App Structure

```
PlongPOC/
├── Config/
│   ├── Config.swift
│   └── APIClient.swift
├── Auth/
│   ├── AuthManager.swift
│   ├── LoginView.swift
│   └── TokenResponse.swift
├── Live/
│   ├── LiveStreamService.swift
│   └── LiveStreamView.swift
├── Footage/
│   ├── FootagePlayerView.swift
│   └── FootagePlayerViewModel.swift
├── Crowd/
│   └── CrowdWebSocketService.swift
├── UI/
│   ├── ContentView.swift
│   ├── ZoneViewModel.swift
│   ├── CameraViewModel.swift
│   ├── SidebarView.swift
│   ├── DetailView.swift
│   └── FootagePlayerView.swift
├── Models/
│   ├── ZoneResponse.swift
│   ├── CameraResponse.swift
│   ├── TaskResponse.swift
│   ├── FootageResponse.swift
│   ├── LiveCrowdResponse.swift
│   └── UserResponse.swift
└── PlongPOCApp.swift
```

---

## 10. Testing Checklist

### Server-Side Verification
- [ ] MediaMTX running: `curl http://localhost:8888/`
- [ ] API health: `curl http://localhost:8080/healthz`
- [ ] Live stream: `curl -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/cameras/cam1/stream`
- [ ] Recorded footage: `curl -H "Authorization: Bearer $TOKEN" http://localhost:8080/api/v1/tasks/{id}/footage/stream`

### iOS App Testing
- [ ] Login flow works
- [ ] Camera list loads
- [ ] Live stream plays (seek, pause work)
- [ ] Recorded footage plays (seek, pause work)
- [ ] WebSocket crowd data updates in real-time
- [ ] Auth persists across app restarts
- [ ] Error handling for network failures

---

## 11. Common Issues & Fixes

| Issue | Solution |
|-------|----------|
| `App Transport Security` blocked | Add `NSAllowsArbitraryLoads` or configure domain exceptions |
| Segments not loading | Verify auth header on segment requests (`AuthResourceLoaderDelegate`) |
| Live stream buffering | Reduce `hlsSegmentDuration` in MediaMTX config |
| WebSocket disconnects | Implement exponential backoff reconnect |
| `401 Unauthorized` on segments | Ensure `AuthResourceLoaderDelegate` adds Bearer to all requests |

---

## 12. Next Steps for Production

1. **HTTPS/TLS** - Configure certificates for production
2. **Token Refresh** - Implement automatic access token refresh
2. **Offline Support** - Cache footage metadata for offline browsing
3. **Push Notifications** - APNs for task alerts
3. **Background Download** - Download footage for offline viewing
4. **Multi-camera Grid** - Simultaneous multi-stream view
4. **Analytics** - Track playback metrics

---

*This guide is based on the Plong Elven codebase as of 2026-11-19. Server endpoints and models may evolve.*