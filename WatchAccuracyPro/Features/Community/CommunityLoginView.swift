import AuthenticationServices
import CryptoKit
import SwiftUI

/// 커뮤니티 로그인 — Sign in with Apple 전용(iOS 네이티브).
/// identity token 을 Supabase 와 교환(`CommunityService.signInWithApple`). 성공 시 onSignedIn.
struct CommunityLoginView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var service = CommunityService.shared
    var onSignedIn: (() -> Void)? = nil

    /// Apple 요청에 보낼 해시 nonce 의 원본 — 교환 시 Supabase 에 raw 로 전달(재생공격 방지).
    @State private var currentNonce: String = ""
    @State private var failed = false
    @State private var working = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.ink3)
            Text(String(localized: "community.login.title"))
                .font(AppTypography.headline)
                .foregroundStyle(AppColors.ink0)
            Text(String(localized: "community.login.body"))
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.ink2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            SignInWithAppleButton(.signIn) { request in
                let nonce = Self.randomNonce()
                currentNonce = nonce
                request.requestedScopes = [.fullName]
                request.nonce = Self.sha256(nonce)
            } onCompletion: { result in
                handle(result)
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .clipShape(Capsule())
            .padding(.horizontal, 32)
            .disabled(working)
            Button(String(localized: "common.cancel")) { dismiss() }
                .font(AppTypography.bodySmall)
                .foregroundStyle(AppColors.ink3)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.paper0)
        .overlay { if working { ProgressView().tint(AppColors.ink0) } }
        .alert(String(localized: "community.login.failed"), isPresented: $failed) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: { Text(service.lastError ?? "") }
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let auth) = result,
              let cred = auth.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = cred.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            failed = true
            return
        }
        working = true
        Task {
            let ok = await service.signInWithApple(idToken: idToken, rawNonce: currentNonce)
            await MainActor.run {
                working = false
                if ok { onSignedIn?(); dismiss() } else { failed = true }
            }
        }
    }

    // MARK: - Nonce (Apple 권장: random + SHA256)

    static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if random < charset.count { result.append(charset[Int(random)]); remaining -= 1 }
        }
        return result
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

#Preview {
    CommunityLoginView()
}
