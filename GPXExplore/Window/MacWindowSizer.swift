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
            }
        }
    }
}
#endif
