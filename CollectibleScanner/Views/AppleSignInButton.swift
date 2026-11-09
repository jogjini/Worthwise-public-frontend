import AuthenticationServices
import SwiftUI

/// Sign in with Apple plus the credit migration that has to follow it.
///
/// Settings presents this (account management). The migration step is easy
/// to forget wherever sign-in is offered, so the caller doesn't own it: this
/// does.
///
/// Failures never surface the raw error (12 Oct run, bug 11: "The operation
/// couldn't be completed. (com.apple.AuthenticationServices.AuthorizationError
/// error 1000.)"). The caller shows `failureMessage` instead (04 ST3).
struct AppleSignInButton: View {
    enum Outcome: Equatable {
        case signedIn
        case cancelled
        case failed
    }

    /// The one failure line (04 §5.6, 06 §4.3).
    static let failureMessage = "Sign in didn't finish. Try again, or carry on without an account."

    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var creditManager: CreditManager
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var buttonHeight: CGFloat = 50

    /// Called when the Apple sheet is requested, so the host can clear an
    /// earlier message before a new attempt.
    let onStart: (() -> Void)?
    /// Called on the main actor once the whole flow (sign-in + migration +
    /// balance refresh) has settled.
    let onOutcome: (Outcome) -> Void

    init(onStart: (() -> Void)? = nil, onOutcome: @escaping (Outcome) -> Void) {
        self.onStart = onStart
        self.onOutcome = onOutcome
    }

    /// 50 pt (grows a little with Dynamic Type), capsule like our buttons (05 §3.13).
    private var height: CGFloat { min(max(buttonHeight, 50), 64) }

    var body: some View {
        SignInWithAppleButton(.signIn) { request in
            request.requestedScopes = []
            onStart?()
        } onCompletion: { result in
            Task { await handle(result) }
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(Capsule())
    }

    private func handle(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                onOutcome(.failed)
                return
            }

            do {
                let oldID = try await authManager.signInWithApple(credential: credential)

                // Move any credits bought while anonymous onto the Apple user
                // key, or signing in would look like it wiped the balance.
                _ = try await APIAnalyzer.migrateCredits(
                    fromUserID: oldID,
                    toUserID: authManager.appleUserID ?? credential.user
                )

                await creditManager.refresh()
                Haptics.notify(.success)
                onOutcome(.signedIn)
            } catch {
                #if DEBUG
                print("[Auth] Sign-in/migration error: \(error.localizedDescription)")
                #endif
                // No haptic on failure (06 §3.2).
                onOutcome(.failed)
            }

        case .failure(let error):
            // Dismissing the sheet is a choice, not an error to report back.
            if (error as? ASAuthorizationError)?.code == .canceled {
                onOutcome(.cancelled)
            } else {
                #if DEBUG
                print("[Auth] Sign-in error: \(error.localizedDescription)")
                #endif
                onOutcome(.failed)
            }
        }
    }
}
