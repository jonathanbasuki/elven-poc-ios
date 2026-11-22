import SwiftUI
import Combine
import AVKit

struct FootagePlayerView: View {
    let task: TaskResponse
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = FootagePlayerViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .onAppear { viewModel.play() }
                    .onDisappear { viewModel.stop() }
            } else if viewModel.isLoading {
                ProgressView("Loading footage...")
                    .foregroundColor(.white)
            } else if let error = viewModel.error {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 50))
                        .foregroundColor(.red)
                    Text(error)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await viewModel.loadFootage(taskId: task.id, token: APIConfig.authToken ?? "") }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("Recorded Footage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .task {
            await viewModel.loadFootage(taskId: task.id, token: APIConfig.authToken ?? "")
        }
    }
}

@MainActor
class FootagePlayerViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isLoading = false
    @Published var error: String?

    func loadFootage(taskId: UUID, token: String) async {
        isLoading = true
        error = nil

        do {
            let footage = try await APIClient.shared.getFootage(taskId: taskId)

            guard let streamPath = footage.url, !streamPath.isEmpty else {
                throw NSError(domain: "Footage", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No stream URL (status: \(footage.status ?? "nil"))"])
            }

            let streamURL = "\(APIConfig.baseURL)\(streamPath)"
            print("🎬 Loading footage: \(streamURL)")
            guard let url = URL(string: streamURL) else {
                error = "Invalid footage URL: \(streamURL)"
                isLoading = false
                return
            }

            let options: [String: Any] = [
                "AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer \(token)"]
            ]
            let asset = AVURLAsset(url: url, options: options)

            let playerItem = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: playerItem)
            self.player = player
        } catch {
            if let apiError = error as? APIError, case .httpError(401, _) = apiError {
                AuthManager.shared.handleUnauthenticated()
            }
            if let apiError = error as? APIError {
                switch apiError {
                case .httpError(_, let data):
                    self.error = String(data: data ?? Data(), encoding: .utf8) ?? error.localizedDescription
                case .decodingError(let underlying, let data):
                    self.error = "Decoding failed: \(underlying.localizedDescription)\nRaw body: \(String(data: data ?? Data(), encoding: .utf8) ?? "nil")"
                default:
                    self.error = error.localizedDescription
                }
            } else {
                self.error = error.localizedDescription
            }
        }

        isLoading = false
    }

    func play() {
        player?.play()
    }

    func stop() {
        player?.pause()
        player = nil
    }
}
