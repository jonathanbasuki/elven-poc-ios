import Foundation
import AVFoundation

class AuthResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {
    private let token: String

    init(token: String) {
        self.token = token
        print("🔑 AuthResourceLoaderDelegate initialized with token: \(token.isEmpty ? "(EMPTY)" : token.prefix(20))")
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let url = loadingRequest.request.url else {
            print("⚠️ Resource loader: no URL")
            loadingRequest.finishLoading(with: NSError(domain: "AuthResourceLoader", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No URL"]))
            return false
        }

        print("📡 Resource loader loading: \(url.lastPathComponent)")

        var request = loadingRequest.request
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            print("🔐 Added Bearer token to \(url.lastPathComponent)")
        } else {
            print("⚠️ No token available for \(url.lastPathComponent)")
        }

        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: nil, delegateQueue: nil)

        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                print("❌ Resource loader error for \(url.lastPathComponent): \(error.localizedDescription)")
                loadingRequest.finishLoading(with: error)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                loadingRequest.finishLoading(with: NSError(domain: "AuthResourceLoader", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
                return
            }

            print("📥 Resource loader response for \(url.lastPathComponent): \(httpResponse.statusCode)")

            if httpResponse.statusCode == 401 {
                print("🔐 Unauthorized - auto logging out")
                AuthManager.shared.handleUnauthenticated()
                loadingRequest.finishLoading(with: NSError(domain: "AuthResourceLoader", code: 401,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid access token"]))
                return
            }

            if !(200...299).contains(httpResponse.statusCode) {
                loadingRequest.finishLoading(with: NSError(domain: "AuthResourceLoader", code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]))
                return
            }

            if let data = data {
                loadingRequest.dataRequest?.respond(with: data)
            }

            loadingRequest.response = httpResponse
            loadingRequest.finishLoading()
        }

        task.resume()
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        print("❌ Resource loader cancelled: \(loadingRequest.request.url?.lastPathComponent ?? "unknown")")
    }
}
