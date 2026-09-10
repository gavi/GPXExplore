#if os(macOS)
import SwiftUI
import AppKit

// Document windows open filling the screen the first time; after that they follow whatever
// size and position the user last left a document window at. AppKit's frame autosave does
// the remembering; this only decides the very first frame.
struct MacWindowSizer: NSViewRepresentable {
    static let autosaveName = "GPXExploreDocumentWindow"

    func makeNSView(context: Context) -> NSView {
        let view = SizerView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class SizerView: NSView {
        private var applied = false
        private var guardToken: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !applied, let window = window else { return }
            applied = true
            // SwiftUI sizes the window after the view lands in it; act after that pass
            DispatchQueue.main.async {
                let saved = UserDefaults.standard.object(forKey: "NSWindow Frame \(MacWindowSizer.autosaveName)") != nil
                if !saved, let screen = window.screen ?? NSScreen.main {
                    window.setFrame(screen.visibleFrame, display: true, animate: false)
                }
                // From here on, every resize or move is saved and restored automatically
                window.setFrameAutosaveName(MacWindowSizer.autosaveName)
                guard saved else { return }
                // SwiftUI's own sizing pass sometimes lands after this one and the window
                // opens at the default document size instead of the remembered frame. For
                // the first moments, put the remembered frame back when anything but a live
                // drag changes it; nobody has had time to resize by hand yet.
                let wanted = window.frame
                let deadline = Date().addingTimeInterval(3)
                self.guardToken = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification, object: window, queue: .main
                ) { [weak self, weak window] _ in
                    guard let self, let window else { return }
                    if Date() > deadline { self.stopGuarding(); return }
                    if !window.inLiveResize, window.frame != wanted {
                        window.setFrame(wanted, display: true, animate: false)
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { self.stopGuarding() }
            }
        }

        private func stopGuarding() {
            if let token = guardToken { NotificationCenter.default.removeObserver(token) }
            guardToken = nil
        }
    }
}
#endif
