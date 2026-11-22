import SwiftUI
import Combine
import AVKit
import AVFoundation

struct LiveStreamView: View {
    let cameraId: String
    let cameraName: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = LiveStreamViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = viewModel.player {
                VideoPlayer(player: player)
                    .aspectRatio(16/9, contentMode: .fit)
                    .onAppear { viewModel.play() }
                    .onDisappear { viewModel.stop() }
            } else if viewModel.isLoading {
                ProgressView("Loading live stream...")
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
                        Task { await viewModel.loadStream(cameraId: cameraId, token: APIConfig.authToken ?? "") }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle(cameraName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .task {
            await viewModel.loadStream(cameraId: cameraId, token: APIConfig.authToken ?? "")
        }
    }
}

@MainActor
class LiveStreamViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isLoading = false
    @Published var error: String?

    func loadStream(cameraId: String, token: String) async {
        isLoading = true
        error = nil

        // MediaMTX HLS stream (direct, no auth needed by default)
        let streamURL = "\(MediaMTXConfig.hlsURL)/\(cameraId)/index.m3u8"
        print("📹 Loading live stream: \(streamURL)")
        guard let url = URL(string: streamURL) else {
            error = "Invalid stream URL"
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
