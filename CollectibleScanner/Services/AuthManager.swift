import AuthenticationServices
import Foundation
import RevenueCat
import UIKit

@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var isSignedIn: Bool = false
    @Published private(set) var appleUserID: String?

    private static let appleUserIDKey = "apple_user_id"

    init() {
        if let stored = UserDefaults.standard.string(forKey: Self.appleUserIDKey), !stored.isEmpty {
            appleUserID = stored
            isSignedIn = true
        }
    }

    // MARK: - Credential Validation

    /// Check if the stored Apple credential is still valid.
    /// Call on launch and when returning to foreground.
    func validateCredential() async {
        guard let userID = appleUserID else { return }

        do {
            let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: userID)
            if state != .authorized {
                // Credential revoked or not found — clear local state
                clearLocal()
            }
        } catch {
            #if DEBUG
            print("[Auth] Credential validation failed: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Sign In

    /// Process a successful Sign in with Apple credential.
    /// Returns the old anonymous RevenueCat user ID for credit migration.
    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async throws -> String {
        let userID = credential.user

        // Capture current anonymous ID before login
        let oldAnonymousID = Purchases.shared.appUserID

        // Log in to RevenueCat with the Apple user ID
        let (_, _) = try await Purchases.shared.logIn(userID)

        // Persist locally
        appleUserID = userID
        isSignedIn = true
        UserDefaults.standard.set(userID, forKey: Self.appleUserIDKey)

        #if DEBUG
        print("[Auth] Signed in: \(userID), old ID: \(oldAnonymousID)")
        #endif

        return oldAnonymousID
    }

    // MARK: - Sign Out

    func signOut() {
        clearLocal()
    }

    // MARK: - Delete Account

    enum DeletionError: LocalizedError {
        case reauthorizationCancelled

        var errorDescription: String? {
            switch self {
            case .reauthorizationCancelled:
                return "Deletion cancelled. Confirm with Apple to delete your account."
            }
        }
    }

    /// Permanently delete the account: server-side credit balance, RevenueCat
    /// subscriber, and the Sign in with Apple token.
    ///
    /// Apple requires that an app offering account creation also offers deletion,
    /// and that Sign in with Apple tokens are revoked (Guideline 5.1.1(v)). Only
    /// Apple's servers can revoke a token, and only in exchange for a *fresh*
    /// authorization code — hence the re-authorization prompt before the call.
    ///
    /// - Returns: the result reported by the server, for diagnostics.
    @discardableResult
    func deleteAccount() async throws -> APIAnalyzer.DeletionResult {
        let appUserID = Purchases.shared.appUserID

        var authorizationCode: String?
        if isSignedIn {
            guard let code = await AppleReauthorizer().requestAuthorizationCode() else {
                throw DeletionError.reauthorizationCancelled
            }
            authorizationCode = code
        }

        let result = try await APIAnalyzer.deleteAccount(
            appUserID: appUserID,
            appleAuthorizationCode: authorizationCode
        )

        // Drop the RevenueCat identity too, so the next launch starts as a brand
        // new anonymous user instead of reviving the ID we just deleted.
        _ = try? await Purchases.shared.logOut()

        clearLocal()

        #if DEBUG
        print("[Auth] Account deleted — rc=\(result.revenueCatDeleted ?? false), apple=\(result.appleCredentialRevoked ?? false)")
        #endif

        return result
    }

    private func clearLocal() {
        appleUserID = nil
        isSignedIn = false
        UserDefaults.standard.removeObject(forKey: Self.appleUserIDKey)
    }
}

// MARK: - Apple re-authorization

/// One-shot wrapper that asks Apple for a fresh authorization code.
///
/// The code returned at sign-in time is single-use and long expired by the time
/// someone decides to delete their account, so revocation needs a new one.
private final class AppleReauthorizer: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    private var continuation: CheckedContinuation<String?, Never>?
    private var retainedSelf: AppleReauthorizer?

    /// Returns the authorization code, or nil if the user cancelled or it failed.
    @MainActor
    func requestAuthorizationCode() async -> String? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            // ASAuthorizationController only holds its delegate weakly.
            self.retainedSelf = self

            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = []

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func finish(with code: String?) {
        continuation?.resume(returning: code)
        continuation = nil
        retainedSelf = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        let credential = authorization.credential as? ASAuthorizationAppleIDCredential
        let code = credential?.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        finish(with: code)
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        #if DEBUG
        print("[Auth] Re-authorization failed: \(error.localizedDescription)")
        #endif
        finish(with: nil)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.keyWindow ?? ASPresentationAnchor()
    }
}
