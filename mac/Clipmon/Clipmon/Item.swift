import AppKit
import CryptoKit
import Foundation
import SwiftData

enum ClipboardContentKind: String, CaseIterable, Codable {
    case text
    case markdown
    case richText
    case spreadsheet
    case image
    case audio
    case file

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .markdown: return "Markdown"
        case .richText: return "Rich Text"
        case .spreadsheet: return "Excel"
        case .image: return "Image"
        case .audio: return "Audio"
        case .file: return "File"
        }
    }

    var sfSymbol: String {
        switch self {
        case .text: return "doc.text"
        case .markdown: return "chevron.left.forwardslash.chevron.right"
        case .richText: return "textformat"
        case .spreadsheet: return "tablecells"
        case .image: return "photo"
        case .audio: return "waveform"
        case .file: return "folder"
        }
    }
}

@Model
final class ClipboardEntry {
    @Attribute(.unique) var fingerprint: String
    var kindRaw: String
    var textContent: String?
    var fileName: String?
    var fileURLString: String?
    var payloadData: Data?
    var utiIdentifier: String?
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var sourceApplication: String?

    var kind: ClipboardContentKind {
        get { ClipboardContentKind(rawValue: kindRaw) ?? .text }
        set { kindRaw = newValue.rawValue }
    }

    init(
        kind: ClipboardContentKind = .text,
        textContent: String? = nil,
        fileName: String? = nil,
        fileURLString: String? = nil,
        payloadData: Data? = nil,
        utiIdentifier: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        isPinned: Bool = false,
        sourceApplication: String? = nil
    ) {
        self.kindRaw = kind.rawValue
        self.textContent = textContent
        self.fileName = fileName
        self.fileURLString = fileURLString
        self.payloadData = payloadData
        self.utiIdentifier = utiIdentifier
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.sourceApplication = sourceApplication
        self.fingerprint = Self.fingerprint(
            kind: kind,
            textContent: textContent,
            fileName: fileName,
            fileURLString: fileURLString,
            payloadData: payloadData,
            utiIdentifier: utiIdentifier
        )
    }
}

extension ClipboardEntry {
    var displayTitle: String {
        switch kind {
        case .text, .markdown, .richText, .spreadsheet:
            return preview
        case .image:
            return fileName ?? "Image"
        case .audio:
            return fileName ?? "Audio"
        case .file:
            return fileName ?? "File"
        }
    }

    var preview: String {
        switch kind {
        case .image:
            return fileName ?? "Image clipboard item"
        case .audio:
            return fileName ?? "Audio clipboard item"
        case .file:
            return fileName ?? "File clipboard item"
        case .text, .markdown, .richText, .spreadsheet:
            let content = (textContent ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if content.isEmpty {
                return "Empty clipboard item"
            }

            if content.count <= 120 {
                return content
            }

            let index = content.index(content.startIndex, offsetBy: 117)
            return String(content[..<index]) + "..."
        }
    }

    var searchableText: String {
        [
            kind.displayName,
            textContent,
            fileName,
            fileURLString,
            utiIdentifier,
            sourceApplication
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
    }

    var fileURL: URL? {
        guard let fileURLString else { return nil }
        return URL(string: fileURLString)
    }

    var image: NSImage? {
        guard kind == .image, let payloadData else { return nil }
        return NSImage(data: payloadData)
    }

    func refresh(
        kind: ClipboardContentKind,
        textContent: String? = nil,
        fileName: String? = nil,
        fileURLString: String? = nil,
        payloadData: Data? = nil,
        utiIdentifier: String? = nil,
        sourceApplication: String?
    ) {
        self.kind = kind
        self.textContent = textContent
        self.fileName = fileName
        self.fileURLString = fileURLString
        self.payloadData = payloadData
        self.utiIdentifier = utiIdentifier
        self.sourceApplication = sourceApplication
        self.updatedAt = .now
        self.createdAt = .now
        self.fingerprint = Self.fingerprint(
            kind: kind,
            textContent: textContent,
            fileName: fileName,
            fileURLString: fileURLString,
            payloadData: payloadData,
            utiIdentifier: utiIdentifier
        )
    }

    static func fingerprint(
        kind: ClipboardContentKind,
        textContent: String?,
        fileName: String?,
        fileURLString: String?,
        payloadData: Data?,
        utiIdentifier: String?
    ) -> String {
        var seed = "\(kind.rawValue)::"
        seed += textContent ?? ""
        seed += "::\(fileName ?? "")"
        seed += "::\(fileURLString ?? "")"
        seed += "::\(utiIdentifier ?? "")"
        if let payloadData {
            seed += "::\(digest(for: payloadData))"
        }
        return digest(for: Data(seed.utf8))
    }

    static func digest(for data: Data) -> String {
        SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }
}

typealias Item = ClipboardEntry
