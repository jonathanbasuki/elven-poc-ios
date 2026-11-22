import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var authManager = AuthManager.shared

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                MainTabView()
            } else {
                LoginView()
            }
        }
        .environmentObject(authManager)
    }
}

struct MainTabView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        TabView {
            LiveCamerasTabView()
                .tabItem {
                    Image(systemName: "video")
                    Text("Live")
                }

            FootageTabView()
                .tabItem {
                    Image(systemName: "film")
                    Text("Footage")
                }
        }
    }
}

// MARK: - Live Cameras Tab (zones -> camera_id for MediaMTX)
struct LiveCamerasTabView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var vm = ZoneViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("Live Cameras")
                        .font(.headline)
                    Spacer()
                    Button("Refresh") {
                        Task { await vm.load() }
                    }
                    .font(.caption)

                    Menu {
                        Button("Logout", role: .destructive) {
                            authManager.logout()
                        }
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.blue)
                    }
                }
                .padding()

                if vm.isLoading {
                    ProgressView("Loading zones...")
                        .frame(maxHeight: .infinity)
                } else if let error = vm.error {
                    CCTVErrorView(message: error, retry: { Task { await vm.load() } })
                } else if vm.zones.isEmpty {
                    CCTVEmptyView(icon: "video.slash", text: "No cameras found")
                } else {
                    List {
                        ForEach(vm.zones) { zone in
                            let cameraId = zone.cameraId ?? zone.zoneId
                            NavigationLink(destination: LiveStreamView(cameraId: cameraId, cameraName: zone.name)) {
                                HStack(spacing: 12) {
                                    Image(systemName: "camera.fill")
                                        .foregroundColor(.blue)
                                        .frame(width: 30)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(zone.name)
                                            .font(.body)
                                        Text("Camera: \(cameraId)  •  Zone: \(zone.zoneId)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Live CCTV")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await vm.load()
            }
        }
    }
}

// MARK: - Footage Tab
struct FootageTabView: View {
    @StateObject private var vm = TaskViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Text("Recorded Footage")
                        .font(.headline)
                    Spacer()
                    Button("Refresh") {
                        Task { await vm.load() }
                    }
                    .font(.caption)
                }
                .padding()

                if vm.isLoading {
                    ProgressView("Loading tasks...")
                        .frame(maxHeight: .infinity)
                } else if let error = vm.error {
                    CCTVErrorView(message: error, retry: { Task { await vm.load() } })
                } else if vm.tasks.isEmpty {
                    CCTVEmptyView(icon: "film.slash", text: "No recorded footage")
                } else {
                    List {
                        ForEach(vm.tasks) { task in
                            NavigationLink(destination: FootagePlayerView(task: task)) {
                                HStack(spacing: 12) {
                                    Image(systemName: "film.fill")
                                        .foregroundColor(.green)
                                        .frame(width: 30)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(task.instruction)
                                            .font(.body)
                                        Text("Status: \(task.status)  •  Zone: \(task.zoneId)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Recordings")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await vm.load()
            }
        }
    }
}

// MARK: - Shared views
struct CCTVErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.red)
            Text(message)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxHeight: .infinity)
        .padding()
    }
}

struct CCTVEmptyView: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text(text)
                .foregroundColor(.secondary)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - ViewModels
@MainActor
class ZoneViewModel: ObservableObject {
    @Published var zones: [ZoneResponse] = []
    @Published var isLoading = false
    @Published var error: String?

    func load() async {
        isLoading = true
        error = nil
        do {
            zones = try await APIClient.shared.getZones()
            print("📍 Zones loaded: \(zones.count)")
            for z in zones {
                print("   - zoneId: \(z.zoneId), name: \(z.name), cameraId: \(z.cameraId ?? "nil")")
            }
        } catch {
            self.error = formatError(error)
        }
        isLoading = false
    }

    private func formatError(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .httpError(_, let data):
                return String(data: data ?? Data(), encoding: .utf8) ?? error.localizedDescription
            case .decodingError(let underlying, let data):
                return "Decoding failed: \(underlying.localizedDescription)\nRaw body: \(String(data: data ?? Data(), encoding: .utf8) ?? "nil")"
            case .serverError(let code, let message):
                return "\(code): \(message)"
            default:
                return error.localizedDescription
            }
        }
        return error.localizedDescription
    }
}

@MainActor
class TaskViewModel: ObservableObject {
    @Published var tasks: [TaskResponse] = []
    @Published var isLoading = false
    @Published var error: String?

    func load() async {
        isLoading = true
        error = nil
        do {
            tasks = try await APIClient.shared.getTasks()
        } catch {
            if let apiError = error as? APIError, case .httpError(401, _) = apiError {
                AuthManager.shared.handleUnauthenticated()
            }
            self.error = formatError(error)
        }
        isLoading = false
    }

    private func formatError(_ error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .httpError(_, let data):
                return String(data: data ?? Data(), encoding: .utf8) ?? error.localizedDescription
            case .decodingError(let underlying, let data):
                return "Decoding failed: \(underlying.localizedDescription)\nRaw body: \(String(data: data ?? Data(), encoding: .utf8) ?? "nil")"
            case .serverError(let code, let message):
                return "\(code): \(message)"
            default:
                return error.localizedDescription
            }
        }
        return error.localizedDescription
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
