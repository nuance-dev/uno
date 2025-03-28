import SwiftUI
import UniformTypeIdentifiers

struct FileItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let type: UTType?
    let size: Int64? // File size in bytes
    var children: [FileItem]? // Nil for files, empty or populated for folders
    var isSelected: Bool = true // Default to selected when added
    var isExpanded: Bool = false // For OutlineGroup state

    // Helper computed properties
    var isDirectory: Bool { children != nil }
    var iconName: String {
        guard let type = type else { return "questionmark.diamond" }
        if isDirectory { return "folder" }
        if type.conforms(to: .sourceCode) { return "curlybraces" }
        if type.conforms(to: .text) { return "doc.text" }
        if type.conforms(to: .pdf) { return "doc.richtext.fill" } // Use filled for PDF
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .data) { return "cylinder.split.1x2" }
        return "doc" // Default document
    }

    // Required for Hashable (using URL which should be unique after resolving symlinks etc.)
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    static func == (lhs: FileItem, rhs: FileItem) -> Bool {
        lhs.url == rhs.url // Uniqueness based on URL
    }
} 