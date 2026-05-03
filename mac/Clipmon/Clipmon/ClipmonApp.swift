import AppKit
import SwiftData
import SwiftUI

@main
struct ClipmonApp: App {
    var body: some Scene {
        WindowGroup("Clipmon") {
            RootLaunchView()
        }
    }
}

private struct RootLaunchView: View {
    @State private var statusBarController = StatusBarController()

    var body: some View {
        Group {
            if #available(macOS 14.0, *) {
                ModernRootView()
            } else {
                LegacySupportView()
            }
        }
        .onAppear {
            statusBarController.ensureStatusItemVisible()
        }
    }
}

@available(macOS 14.0, *)
private struct ModernRootView: View {
    @StateObject private var controller = ClipboardHistoryController()

    var body: some View {
        ContentView()
            .environmentObject(controller)
            .modelContainer(ClipmonModelStore.sharedModelContainer)
    }
}

@available(macOS 14.0, *)
private enum ClipmonModelStore {
    static let sharedModelContainer: ModelContainer = {
        let schema = Schema([ClipboardEntry.self])
        let configuration = ModelConfiguration(
            "Clipmon",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .automatic,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
}

@MainActor
final class StatusBarController: NSObject {
    private let popover = NSPopover()
    private let statusItem: NSStatusItem

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        configureStatusItem()
    }

    func ensureStatusItemVisible() {
        configureStatusItem()

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 540)

        if #available(macOS 14.0, *) {
            popover.contentViewController = NSHostingController(
                rootView: MenuBarView()
                    .environmentObject(ClipboardHistoryController.shared)
                    .modelContainer(ClipmonModelStore.sharedModelContainer)
            )
        } else {
            popover.contentViewController = NSHostingController(rootView: LegacySupportView())
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        if button.image == nil {
            button.image = NSImage(
                systemSymbolName: "doc.on.clipboard",
                accessibilityDescription: "Clipmon"
            )?.withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
        }

        button.title = ""
        button.toolTip = "Clipmon"
        button.imagePosition = .imageOnly
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private struct LegacySupportView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 42, weight: .semibold))
                .foregroundColor(.secondary)

            Text("Clipmon")
                .font(.title.weight(.semibold))

            Text("This build includes the modern clipboard manager on macOS 14 and later. On macOS 11 to 13, the app opens in a compatibility view so the project can still build cleanly.")
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 420, minHeight: 240, alignment: .leading)
        .padding(24)
    }
}
