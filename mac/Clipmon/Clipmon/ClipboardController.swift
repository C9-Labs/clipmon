import AppKit
import Combine
import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardCapturePayload {
    let kind: ClipboardContentKind
    let textContent: String?
    let fileName: String?
    let fileURLString: String?
    let payloadData: Data?
    let utiIdentifier: String?
    let sourceApplication: String?

    var fingerprint: String {
        ClipboardEntry.fingerprint(
            kind: kind,
            textContent: textContent,
            fileName: fileName,
            fileURLString: fileURLString,
            payloadData: payloadData,
            utiIdentifier: utiIdentifier
        )
    }
}

@MainActor
final class ClipboardHistoryController: ObservableObject {
    @Published var searchText = ""
    @Published var isMonitoring = false
    @Published var statusMessage = "Ready to watch the clipboard"

    private var modelContext: ModelContext?
    private var pollTimer: Timer?
    private var lastObservedChangeCount: Int = NSPasteboard.general.changeCount

    func startIfNeeded(modelContext: ModelContext) {
        guard pollTimer == nil else { return }

        self.modelContext = modelContext
        isMonitoring = true
        statusMessage = "Watching clipboard changes"
        captureCurrentClipboard(force: true)

        let timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureCurrentClipboard()
            }
        }
        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        isMonitoring = false
        statusMessage = "Clipboard monitoring paused"
    }

    func togglePin(_ entry: ClipboardEntry) {
        entry.isPinned.toggle()
        entry.updatedAt = .now
        saveContext()
    }

    func delete(_ entry: ClipboardEntry) {
        modelContext?.delete(entry)
        saveContext()
    }

    func clearHistory(keepingPinned: Bool = true) {
        guard let modelContext else { return }

        let descriptor = FetchDescriptor<ClipboardEntry>()
        do {
            let entries = try modelContext.fetch(descriptor)
            for entry in entries where !(keepingPinned && entry.isPinned) {
                modelContext.delete(entry)
            }
            saveContext()
            statusMessage = keepingPinned ? "Cleared unpinned items" : "Cleared clipboard history"
        } catch {
            statusMessage = "Could not clear history"
        }
    }

    func copyToClipboard(_ entry: ClipboardEntry) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch entry.kind {
        case .text, .markdown:
            pasteboard.setString(entry.textContent ?? "", forType: .string)
        case .richText:
            if let payloadData = entry.payloadData {
                pasteboard.setData(payloadData, forType: .rtf)
            } else {
                pasteboard.setString(entry.textContent ?? "", forType: .string)
            }
        case .spreadsheet:
            if let fileURL = entry.fileURL {
                pasteboard.writeObjects([fileURL as NSURL])
            } else {
                pasteboard.setString(entry.textContent ?? "", forType: .string)
            }
        case .image:
            if let image = entry.image ?? entry.fileURL.flatMap({ NSImage(contentsOf: $0) }) {
                pasteboard.writeObjects([image])
            } else if let payloadData = entry.payloadData {
                pasteboard.setData(payloadData, forType: .tiff)
            }
        case .audio, .file:
            if let fileURL = entry.fileURL {
                pasteboard.writeObjects([fileURL as NSURL])
            }
        }

        lastObservedChangeCount = pasteboard.changeCount
        statusMessage = "Copied \(entry.kind.displayName.lowercased()) back to clipboard"
        entry.updatedAt = .now
        saveContext()
    }

    func captureCurrentClipboard(force: Bool = false) {
        guard let modelContext else { return }

        let pasteboard = NSPasteboard.general
        guard force || pasteboard.changeCount != lastObservedChangeCount else { return }
        lastObservedChangeCount = pasteboard.changeCount

        guard let payload = payloadFromPasteboard(pasteboard) else {
            statusMessage = "Clipboard changed, but nothing supported was found"
            return
        }

        save(payload: payload)
    }

    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty, modelContext != nil else { return }

        for url in urls where url.isFileURL {
            let payload = payloadFromFile(url, sourceApplication: NSWorkspace.shared.frontmostApplication?.localizedName)
            save(payload: payload)
        }

        statusMessage = "Imported \(urls.count) file(s) into history"
    }

    func filteredEntries(from entries: [ClipboardEntry], pinnedOnly: Bool = false) -> [ClipboardEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return entries
            .filter { !pinnedOnly || $0.isPinned }
            .sorted {
                if $0.isPinned != $1.isPinned {
                    return $0.isPinned && !$1.isPinned
                }
                return $0.updatedAt > $1.updatedAt
            }
            .filter { entry in
                guard !query.isEmpty else { return true }
                return entry.searchableText.contains(query)
            }
    }

    private func save(payload: ClipboardCapturePayload) {
        guard let modelContext else { return }
        let fingerprint = payload.fingerprint

        let descriptor = FetchDescriptor<ClipboardEntry>(
            predicate: #Predicate { $0.fingerprint == fingerprint }
        )

        do {
            if let existing = try modelContext.fetch(descriptor).first {
                existing.refresh(
                    kind: payload.kind,
                    textContent: payload.textContent,
                    fileName: payload.fileName,
                    fileURLString: payload.fileURLString,
                    payloadData: payload.payloadData,
                    utiIdentifier: payload.utiIdentifier,
                    sourceApplication: payload.sourceApplication
                )
            } else {
                let entry = ClipboardEntry(
                    kind: payload.kind,
                    textContent: payload.textContent,
                    fileName: payload.fileName,
                    fileURLString: payload.fileURLString,
                    payloadData: payload.payloadData,
                    utiIdentifier: payload.utiIdentifier,
                    sourceApplication: payload.sourceApplication
                )
                modelContext.insert(entry)
            }

            saveContext()
            statusMessage = "Captured \(payload.kind.displayName.lowercased()) item"
        } catch {
            statusMessage = "Failed to save clipboard item"
        }
    }

    private func payloadFromPasteboard(_ pasteboard: NSPasteboard) -> ClipboardCapturePayload? {
        let sourceApplication = NSWorkspace.shared.frontmostApplication?.localizedName

        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            NSPasteboard.ReadingOptionKey.urlReadingFileURLsOnly: true
        ]) as? [URL], let first = fileURLs.first {
            return payloadFromFile(first, sourceApplication: sourceApplication)
        }

        if let image = NSImage(pasteboard: pasteboard), let tiffData = image.tiffRepresentation {
            return ClipboardCapturePayload(
                kind: .image,
                textContent: nil,
                fileName: nil,
                fileURLString: nil,
                payloadData: tiffData,
                utiIdentifier: UTType.image.identifier,
                sourceApplication: sourceApplication
            )
        }

        if let rtfData = pasteboard.data(forType: .rtf) {
            return ClipboardCapturePayload(
                kind: .richText,
                textContent: pasteboard.string(forType: .string),
                fileName: nil,
                fileURLString: nil,
                payloadData: rtfData,
                utiIdentifier: UTType.rtf.identifier,
                sourceApplication: sourceApplication
            )
        }

        if let spreadsheetKind = spreadsheetKind(for: pasteboard) {
            return ClipboardCapturePayload(
                kind: spreadsheetKind,
                textContent: pasteboard.string(forType: .string),
                fileName: nil,
                fileURLString: nil,
                payloadData: nil,
                utiIdentifier: UTType.spreadsheet.identifier,
                sourceApplication: sourceApplication
            )
        }

        if let string = pasteboard.string(forType: .string) {
            return ClipboardCapturePayload(
                kind: markdownLike(string) ? .markdown : .text,
                textContent: string,
                fileName: nil,
                fileURLString: nil,
                payloadData: nil,
                utiIdentifier: UTType.plainText.identifier,
                sourceApplication: sourceApplication
            )
        }

        return nil
    }

    private func payloadFromFile(_ url: URL, sourceApplication: String?) -> ClipboardCapturePayload {
        let kind = fileKind(for: url)
        let data = kind == .image ? try? Data(contentsOf: url) : nil

        return ClipboardCapturePayload(
            kind: kind,
            textContent: kind == .spreadsheet ? (try? String(contentsOf: url)) : nil,
            fileName: url.lastPathComponent,
            fileURLString: url.absoluteString,
            payloadData: data,
            utiIdentifier: UTType(filenameExtension: url.pathExtension)?.identifier,
            sourceApplication: sourceApplication
        )
    }

    private func fileKind(for url: URL) -> ClipboardContentKind {
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "heic", "gif", "tiff", "bmp", "webp":
            return .image
        case "mp3", "m4a", "aac", "wav", "flac", "aiff", "ogg":
            return .audio
        case "xls", "xlsx", "csv", "numbers":
            return .spreadsheet
        case "rtf", "rtfd":
            return .richText
        case "md", "markdown", "txt":
            return .markdown
        default:
            return .file
        }
    }

    private func spreadsheetKind(for pasteboard: NSPasteboard) -> ClipboardContentKind? {
        let knownTypes: [NSPasteboard.PasteboardType] = [
            .init(UTType.spreadsheet.identifier),
            .init("com.microsoft.excel.xls"),
            .init("org.openxmlformats.spreadsheetml.sheet"),
            .init("public.comma-separated-values-text")
        ]

        if let available = pasteboard.types, available.contains(where: { knownTypes.contains($0) }) {
            return .spreadsheet
        }

        if let string = pasteboard.string(forType: .string),
           string.contains("\t"),
           string.contains("\n") {
            return .spreadsheet
        }

        return nil
    }

    private func markdownLike(_ string: String) -> Bool {
        let lowercased = string.lowercased()
        return lowercased.contains("\n#")
            || lowercased.contains("```")
            || lowercased.contains("[")
            || lowercased.contains("](")
            || lowercased.contains("- ")
            || lowercased.contains("* ")
    }

    private func saveContext() {
        guard let modelContext else { return }

        do {
            try modelContext.save()
        } catch {
            statusMessage = "Could not save clipboard history"
        }
    }
}
