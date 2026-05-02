import AppKit
import SwiftData
import SwiftUI

struct MenuBarView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var controller: ClipboardHistoryController
    @Environment(\.openWindow) private var openWindow

    @Query(sort: [SortDescriptor(\ClipboardEntry.updatedAt, order: .reverse)])
    private var entries: [ClipboardEntry]

    private var recentEntries: [ClipboardEntry] {
        controller.filteredEntries(from: entries).prefix(5).map { $0 }
    }

    private var searchResults: [ClipboardEntry] {
        controller.filteredEntries(from: entries)
    }

    private var hasSearchText: Bool {
        !controller.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            TextField("Search clipboard", text: $controller.searchText)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 8) {
                Button {
                    openMainWindow()
                } label: {
                    Label("Open Window", systemImage: "window.zoomedin")
                }

                Button {
                    controller.captureCurrentClipboard(force: true)
                } label: {
                    Label("Capture", systemImage: "arrow.down.doc")
                }
            }
            .buttonStyle(.bordered)

            HStack(spacing: 8) {
                Button {
                    if controller.isMonitoring {
                        controller.stop()
                    } else {
                        controller.startIfNeeded(modelContext: modelContext)
                    }
                } label: {
                    Label(controller.isMonitoring ? "Pause" : "Resume", systemImage: controller.isMonitoring ? "pause.fill" : "play.fill")
                }

                Button(role: .destructive) {
                    controller.clearHistory(keepingPinned: true)
                } label: {
                    Label("Clear Unpinned", systemImage: "trash")
                }
            }
            .buttonStyle(.bordered)

            Divider()

            if hasSearchText {
                Text("Search Results")
                    .font(.headline)

                if searchResults.isEmpty {
                    Text("No results for “\(controller.searchText)”")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(searchResults, id: \.fingerprint) { entry in
                            MenuBarEntryRow(entry: entry) {
                                controller.copyToClipboard(entry)
                            } onPinToggle: {
                                controller.togglePin(entry)
                            }
                        }
                    }
                }
            } else {
                if recentEntries.isEmpty {
                    Text("No clipboard items yet")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Clips")
                            .font(.headline)

                        ForEach(recentEntries, id: \.fingerprint) { entry in
                            MenuBarEntryRow(entry: entry) {
                                controller.copyToClipboard(entry)
                            } onPinToggle: {
                                controller.togglePin(entry)
                            }
                        }
                    }
                }
            }

            Divider()

            HStack {
                Text(controller.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .frame(width: 360)
        .onAppear {
            controller.startIfNeeded(modelContext: modelContext)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Clipmon", systemImage: "doc.on.clipboard")
                    .font(.headline)

                Spacer()

                Image(systemName: controller.isMonitoring ? "dot.radiowaves.left.and.right" : "pause.circle")
                    .foregroundStyle(controller.isMonitoring ? .green : .secondary)
            }

            Text("Clipboard history in the menu bar")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(controller.statusMessage)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func openMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct MenuBarEntryRow: View {
    let entry: ClipboardEntry
    let onCopy: () -> Void
    let onPinToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onCopy) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(entry.kind.displayName, systemImage: entry.kind.sfSymbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(entry.displayTitle)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if entry.isPinned {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .buttonStyle(.plain)

            HStack {
                Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(.secondary)
                if let fileName = entry.fileName {
                    Text("•")
                    Text(fileName)
                        .lineLimit(1)
                }
                Spacer()
                Button(entry.isPinned ? "Unpin" : "Pin", action: onPinToggle)
                    .buttonStyle(.plain)
            }
            .font(.caption)
        }
        .padding(10)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
