import AppKit
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ClipboardHistoryController
    @Query(sort: [SortDescriptor(\ClipboardEntry.updatedAt, order: .reverse)])
    private var entries: [ClipboardEntry]

    @State private var selectionFingerprint: String?
    @State private var scope: EntryScope = .all
    @State private var showingClearConfirmation = false
    @State private var mainWindow: NSWindow?
    @State private var wasHiddenBeforeDrag = false
    @State private var isFileDragActive = false

    init() {}

    private var filteredEntries: [ClipboardEntry] {
        controller.filteredEntries(from: entries, pinnedOnly: scope == .pinned)
    }

    private var selectedEntry: ClipboardEntry? {
        if let selectionFingerprint {
            return filteredEntries.first(where: { $0.fingerprint == selectionFingerprint })
        }

        return filteredEntries.first
    }

    private var pinnedCount: Int {
        entries.filter(\.isPinned).count
    }

    var body: some View {
        GeometryReader { proxy in
            let isCompactLayout = proxy.size.width < 980

            NavigationSplitView {
                GeometryReader { sidebarProxy in
                    let sidebarLayout = SidebarLayout(width: sidebarProxy.size.width)

                    sidebar(isCompact: sidebarLayout.isCompact, isVeryCompact: sidebarLayout.isVeryCompact)
                }
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
                    .navigationTitle("Clipmon")
            } detail: {
                detailPane(isCompact: isCompactLayout)
            }
            .frame(minWidth: 920, minHeight: 660)
            .background(backgroundGradient)
            .searchable(text: $controller.searchText, placement: .sidebar, prompt: "Search clipboard history")
            .toolbar {
                ToolbarItemGroup {
                    Button {
                        controller.captureCurrentClipboard(force: true)
                    } label: {
                        toolbarLabel("Capture Now", icon: "arrow.down.doc", compact: isCompactLayout)
                    }

                    Button {
                        if controller.isMonitoring {
                            controller.stop()
                        } else {
                            controller.startIfNeeded(modelContext: modelContext)
                        }
                    } label: {
                        toolbarLabel(
                            controller.isMonitoring ? "Pause" : "Resume",
                            icon: controller.isMonitoring ? "pause.fill" : "play.fill",
                            compact: isCompactLayout
                        )
                    }

                    Button(role: .destructive) {
                        showingClearConfirmation = true
                    } label: {
                        toolbarLabel("Clear", icon: "trash", compact: isCompactLayout)
                    }
                }
            }
            .confirmationDialog(
                "Clear clipboard history?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Unpinned", role: .destructive) {
                    controller.clearHistory(keepingPinned: true)
                }

                Button("Clear Everything", role: .destructive) {
                    controller.clearHistory(keepingPinned: false)
                }
            } message: {
                Text("Pinned entries can be preserved so you do not lose important clips.")
            }
            .onAppear {
                controller.startIfNeeded(modelContext: modelContext)
            }
            .background(
                WindowAccessor { window in
                    mainWindow = window
                }
            )
            .onChange(of: filteredEntries.map(\.fingerprint)) { _, newValue in
                if let selectionFingerprint, !newValue.contains(selectionFingerprint) {
                    self.selectionFingerprint = newValue.first
                } else if selectionFingerprint == nil {
                    self.selectionFingerprint = newValue.first
                }
            }
        }
    }

    private func toolbarLabel(_ title: String, icon: String, compact: Bool) -> some View {
        Group {
            if compact {
                Image(systemName: icon)
            } else {
                Label(title, systemImage: icon)
            }
        }
    }

    private func sidebar(isCompact: Bool, isVeryCompact: Bool) -> some View {
        VStack(spacing: isCompact ? 12 : 16) {
            headerCard(isCompact: isCompact)

            FileDropZoneView(isCompact: isCompact, isVeryCompact: isVeryCompact) { urls in
                controller.importFiles(urls)
                endFileDragSession()
            } onDragStateChange: { isTargeted in
                isFileDragActive = isTargeted

                if isTargeted {
                    beginFileDragSession()
                } else {
                    endFileDragSession()
                }
            }
            .scaleEffect(isFileDragActive ? 1.01 : 1.0)

            Picker("Scope", selection: $scope) {
                ForEach(EntryScope.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            statsRow(isCompact: isCompact, isVeryCompact: isVeryCompact)

            List(filteredEntries, id: \.fingerprint) { entry in
                ClipboardEntryRow(entry: entry, isCompact: isCompact, isVeryCompact: isVeryCompact)
                    .listRowBackground(selectionFingerprint == entry.fingerprint ? Color.accentColor.opacity(0.14) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectionFingerprint = entry.fingerprint
                    }
                    .contextMenu {
                        Button("Copy") {
                            controller.copyToClipboard(entry)
                        }

                        Button(entry.isPinned ? "Unpin" : "Pin") {
                            controller.togglePin(entry)
                        }

                        Button("Delete", role: .destructive) {
                            if selectionFingerprint == entry.fingerprint {
                                selectionFingerprint = nil
                            }
                            controller.delete(entry)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            controller.copyToClipboard(entry)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .trailing) {
                        Button {
                            controller.togglePin(entry)
                        } label: {
                            Label(entry.isPinned ? "Unpin" : "Pin", systemImage: "pin")
                        }
                        .tint(.orange)
                    }
            }
            .listStyle(.sidebar)
        }
        .padding(isCompact ? 12 : 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(isCompact ? 12 : 16)
    }

    private func detailPane(isCompact: Bool) -> some View {
        Group {
            if let entry = selectedEntry {
                ClipboardDetailView(
                    entry: entry,
                    isCompact: isCompact,
                    onCopy: { controller.copyToClipboard(entry) },
                    onTogglePin: { controller.togglePin(entry) },
                    onDelete: {
                        if selectionFingerprint == entry.fingerprint {
                            selectionFingerprint = nil
                        }
                        controller.delete(entry)
                    }
                )
            } else {
                EmptyStateView(
                    isMonitoring: controller.isMonitoring,
                    statusMessage: controller.statusMessage,
                    totalCount: entries.count
                )
            }
        }
        .padding(24)
        .animation(.snappy, value: selectedEntry?.fingerprint)
    }

    private func headerCard(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Clipboard Vault", systemImage: "tray.full")
                    .font(isCompact ? .headline.weight(.semibold) : .title2.weight(.semibold))
                Spacer()
                Capsule()
                    .fill(controller.isMonitoring ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                    .overlay(
                        Group {
                            Text(controller.isMonitoring ? "Live" : "Paused")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(controller.isMonitoring ? .green : .orange)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                        }
                    )
                    .frame(height: isCompact ? 24 : 28)
            }

            Text("A local clipboard manager backed by SwiftData.")
                .font(isCompact ? .caption : .subheadline)
                .foregroundStyle(.secondary)

            Text(controller.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isCompact ? 12 : 16)
        .background(
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.20),
                    Color.teal.opacity(0.10),
                    Color.indigo.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private func statsRow(isCompact: Bool, isVeryCompact: Bool) -> some View {
        HStack(spacing: 12) {
            StatCard(title: "Total", value: "\(entries.count)", systemImage: "list.bullet.rectangle", isCompact: isCompact, isVeryCompact: isVeryCompact)
            StatCard(title: "Pinned", value: "\(pinnedCount)", systemImage: "pin", isCompact: isCompact, isVeryCompact: isVeryCompact)
            StatCard(title: "Visible", value: "\(filteredEntries.count)", systemImage: "magnifyingglass", isCompact: isCompact, isVeryCompact: isVeryCompact)
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color.blue.opacity(0.05),
                Color.cyan.opacity(0.06)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

private enum EntryScope: String, CaseIterable {
    case all
    case pinned

    var title: String {
        switch self {
        case .all:
            return "All"
        case .pinned:
            return "Pinned"
        }
    }
}

struct SidebarLayout {
    let width: CGFloat

    var isCompact: Bool {
        width < 420
    }

    var isVeryCompact: Bool {
        width < 340
    }
}

private struct ClipboardEntryRow: View {
    let entry: ClipboardEntry
    let isCompact: Bool
    let isVeryCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(entry.kind.displayName, systemImage: entry.kind.sfSymbol)
                    .font(isCompact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(entry.displayTitle)
                    .font(isCompact ? .callout : .body)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Spacer(minLength: 8)

                if entry.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 8) {
                Label(entry.createdAt.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                if let sourceApplication = entry.sourceApplication {
                    Text("•")
                    Text(sourceApplication)
                }
                if let fileName = entry.fileName {
                    Text("•")
                    Text(fileName)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, isCompact ? 2 : 4)
    }
}

private struct ClipboardDetailView: View {
    let entry: ClipboardEntry
    let isCompact: Bool
    let onCopy: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: isCompact ? 14 : 20) {
                VStack(alignment: .leading, spacing: isCompact ? 8 : 12) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: isCompact ? 4 : 6) {
                            Label(entry.kind.displayName, systemImage: entry.kind.sfSymbol)
                                .font(.headline)
                                .foregroundStyle(.secondary)

                            Text(entry.displayTitle)
                                .font(isCompact ? .headline.weight(.semibold) : .title2.weight(.semibold))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        if entry.isPinned {
                            Image(systemName: "pin.fill")
                                .font(.title3)
                                .foregroundStyle(.orange)
                        }
                    }

                    HStack(spacing: isCompact ? 8 : 10) {
                        DetailChip(icon: "clock", text: entry.createdAt.formatted(date: .abbreviated, time: .shortened))

                        if let sourceApplication = entry.sourceApplication {
                            DetailChip(icon: "desktopcomputer", text: sourceApplication)
                        }

                        if let fileName = entry.fileName {
                            DetailChip(icon: "doc", text: fileName)
                        }

                        DetailChip(icon: entry.kind.sfSymbol, text: entry.kind.displayName)
                    }
                }
                .padding(isCompact ? 14 : 20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))

                if let image = entry.image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: isCompact ? 320 : 420)
                        .padding(isCompact ? 8 : 12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                VStack(alignment: .leading, spacing: isCompact ? 10 : 12) {
                    HStack {
                        Text("Content")
                            .font(isCompact ? .subheadline.weight(.semibold) : .headline)

                        Spacer()

                        Button("Copy") {
                            onCopy()
                        }
                        .buttonStyle(.borderedProminent)

                        Button(entry.isPinned ? "Unpin" : "Pin") {
                            onTogglePin()
                        }
                        .buttonStyle(.bordered)

                        Button("Delete", role: .destructive) {
                            onDelete()
                        }
                        .buttonStyle(.bordered)
                    }

                    Text(entry.textContent ?? entry.preview)
                        .textSelection(.enabled)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(isCompact ? 12 : 16)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .frame(maxWidth: isCompact ? 700 : 760, alignment: .leading)
        }
    }
}

private struct DetailChip: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.8), in: Capsule())
    }
}

private struct StatCard: View {
    let title: String
    let value: String
    let systemImage: String
    let isCompact: Bool
    let isVeryCompact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: isVeryCompact ? 2 : 6) {
            Label(title, systemImage: systemImage)
                .font(isCompact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(isVeryCompact ? .headline.weight(.semibold) : .title2.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isVeryCompact ? 10 : 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct EmptyStateView: View {
    let isMonitoring: Bool
    let statusMessage: String
    let totalCount: Int

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "clipboard")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text(totalCount == 0 ? "Your clipboard history is empty" : "No clip matches your search")
                    .font(.title3.weight(.semibold))

                Text(isMonitoring
                     ? "Copy any text anywhere and it will appear here automatically."
                     : "Resume monitoring to keep saving clipboard items.")
                .foregroundStyle(.secondary)
            }

            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

private struct FileDropZoneView: View {
    let isCompact: Bool
    let isVeryCompact: Bool
    let onDropFiles: ([URL]) -> Void
    let onDragStateChange: ((Bool) -> Void)?
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 4 : 8) {
            HStack {
                Image(systemName: "square.and.arrow.down")
                Text("Drop files here")
                    .font(isCompact ? .subheadline.weight(.semibold) : .headline)
                Spacer()
            }

            Text("Import images, audio, spreadsheets, documents, or folders into clipboard history.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(isVeryCompact ? 10 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isTargeted ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.35))
        )
        .overlay(
            Group {
                if isTargeted {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Release to import")
                            .font(.subheadline.weight(.semibold))
                        Text("Clipmon is ready to receive files.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        )
        .dropDestination(for: URL.self) { urls, _ in
            onDropFiles(urls)
            return true
        } isTargeted: {
            isTargeted = $0
            onDragStateChange?($0)
        }
    }
}

private extension ContentView {
    func beginFileDragSession() {
        guard let mainWindow else { return }

        wasHiddenBeforeDrag = !mainWindow.isVisible
        if wasHiddenBeforeDrag {
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            mainWindow.orderFrontRegardless()
        }
    }

    func endFileDragSession() {
        guard wasHiddenBeforeDrag else {
            wasHiddenBeforeDrag = false
            isFileDragActive = false
            return
        }

        wasHiddenBeforeDrag = false
        isFileDragActive = false
        mainWindow?.orderOut(nil)
    }
}

private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            onResolve(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            onResolve(nsView.window)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ClipboardHistoryController())
        .modelContainer(for: [ClipboardEntry.self], inMemory: true)
}
