import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var error: String?
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        NavigationStack {
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
                    if let apiError = error as? APIError {
                        switch apiError {
                        case .httpError(_, let data):
                            self.error = String(data: data ?? Data(), encoding: .utf8) ?? error.localizedDescription
                        case .decodingError(_, let data):
                            self.error = "Decoding failed: \(error.localizedDescription)\nRaw body: \(String(data: data ?? Data(), encoding: .utf8) ?? "nil")"
                        default:
                            self.error = error.localizedDescription
                        }
                    } else {
                        self.error = error.localizedDescription
                    }
                    isLoading = false
                }
            }
        }
    }
}
