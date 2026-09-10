import Foundation
import StoreKit
#if os(iOS)
import UIKit
#endif

// Asks for an App Store rating after a good moment (a file opened, an export done): never
// before the third such moment and at most once per version. Apple decides whether anything
// is shown; this only asks. A listing with no ratings loses the next searcher, and nothing
// asked before this existed.
enum ReviewPrompt {
    private static let momentsKey = "reviewPrompt.goodMoments"
    private static let askedVersionKey = "reviewPrompt.askedVersion"
    private static let threshold = 3

    static func goodMoment() {
        let defaults = UserDefaults.standard
        let moments = defaults.integer(forKey: momentsKey) + 1
        defaults.set(moments, forKey: momentsKey)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        guard moments >= threshold, defaults.string(forKey: askedVersionKey) != version else { return }
        defaults.set(version, forKey: askedVersionKey)
        // A beat after the moment, so the prompt does not land on top of a sheet or a share panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { request() }
    }

    @MainActor
    private static func request() {
        #if os(iOS)
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        SKStoreReviewController.requestReview(in: scene)
        #elseif os(macOS)
        SKStoreReviewController.requestReview()
        #endif
    }
}
