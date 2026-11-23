import AppKit
import SwiftUI

/// Ссылка на окно настроек, чтобы не открывать второе и поднимать существующее.
enum SettingsWindow {
    static weak var window: NSWindow?
    static let title = "fmt"

    static func configure(_ window: NSWindow?) {
        window?.title = title
    }
}

/// Берёт реальное NSWindow из SwiftUI-окна.
struct SettingsWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            SettingsWindow.window = view.window
            SettingsWindow.configure(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        SettingsWindow.configure(nsView.window)
    }
}
