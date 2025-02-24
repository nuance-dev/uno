import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import os
import Foundation
import Highlightr // For syntax highlighting

private let logger = Logger(subsystem: "me.nuanc.Uno", category: "FileProcessor")

class FileProcessor: ObservableObject {
    @Published var files: [URL] = [] {
        didSet {
            if !files.isEmpty {
                processFiles(mode: currentMode)
            } else {
                processedContent = ""
                processedPDF = nil
                fileTree = nil
                processedAttributedContent = nil
            }
        }
    }
    @Published private(set) var currentMode: ContentView.Mode = .prompt
    @Published var isProcessing = false
    @Published var processedContent: String = ""
    @Published var processedAttributedContent: NSAttributedString?
    @Published var processedPDF: PDFDocument?
    @Published var error: String?
    @Published var progress: Double = 0
    @Published private(set) var lastProcessedFiles: [URL] = []
    @Published var fileTree: FileNode?
    @Published var includeFileTree: Bool = false
    @Published var promptFormat: PromptFormat = .standard
    @Published var useSyntaxHighlighting: Bool = true
    @Published var pdfTheme: PDFTheme = .light
    
    // Highlighter for syntax highlighting
    private let highlighter = Highlightr()
    
    enum PromptFormat: String, CaseIterable, Identifiable {
        case standard = "Standard"
        case fileTree = "With File Tree"
        case markdown = "Markdown"
        
        var id: String { self.rawValue }
    }
    
    enum PDFTheme: String, CaseIterable, Identifiable {
        case light = "Light (Xcode)"
        case dark = "Dark (Atom One)"
        case github = "GitHub"
        case monokai = "Monokai"
        case solarizedLight = "Solarized Light"
        
        var id: String { self.rawValue }
        
        var themeName: String {
            switch self {
            case .light: return "xcode"
            case .dark: return "atom-one-dark"
            case .github: return "github"
            case .monokai: return "monokai"
            case .solarizedLight: return "solarized-light"
            }
        }
        
        var backgroundColor: CGColor {
            switch self {
            case .light: return CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
            case .dark: return CGColor(red: 0.16, green: 0.18, blue: 0.2, alpha: 1.0)
            case .github: return CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
            case .monokai: return CGColor(red: 0.14, green: 0.15, blue: 0.13, alpha: 1.0)
            case .solarizedLight: return CGColor(red: 0.99, green: 0.96, blue: 0.89, alpha: 1.0)
            }
        }
        
        var textColor: NSColor {
            switch self {
            case .light: return NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
            case .github: return NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
            case .solarizedLight: return NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
            case .dark: return NSColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1.0)
            case .monokai: return NSColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1.0)
            }
        }
        
        var lineNumberColor: NSColor {
            switch self {
            case .light, .github: return NSColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
            case .solarizedLight: return NSColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1.0)
            case .dark: return NSColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0)
            case .monokai: return NSColor(red: 0.6, green: 0.6, blue: 0.6, alpha: 1.0)
            }
        }
        
        var headerBackgroundColors: [CGColor] {
            switch self {
            case .light, .github:
                return [
                    CGColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0),
                    CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
                ]
            case .dark:
                return [
                    CGColor(red: 0.22, green: 0.24, blue: 0.27, alpha: 1.0),
                    CGColor(red: 0.16, green: 0.18, blue: 0.2, alpha: 1.0)
                ]
            case .monokai:
                return [
                    CGColor(red: 0.18, green: 0.19, blue: 0.17, alpha: 1.0),
                    CGColor(red: 0.14, green: 0.15, blue: 0.13, alpha: 1.0)
                ]
            case .solarizedLight:
                return [
                    CGColor(red: 0.92, green: 0.91, blue: 0.84, alpha: 1.0),
                    CGColor(red: 0.99, green: 0.96, blue: 0.89, alpha: 1.0)
                ]
            }
        }
        
        var codeBackgroundColor: CGColor {
            switch self {
            case .light: 
                return CGColor(red: 0.98, green: 0.98, blue: 0.98, alpha: 1.0)
            case .github: 
                return CGColor(red: 0.97, green: 0.97, blue: 0.97, alpha: 1.0)
            case .dark: 
                return CGColor(red: 0.2, green: 0.22, blue: 0.25, alpha: 1.0)
            case .monokai: 
                return CGColor(red: 0.17, green: 0.18, blue: 0.16, alpha: 1.0)
            case .solarizedLight: 
                return CGColor(red: 0.95, green: 0.93, blue: 0.86, alpha: 1.0)
            }
        }
        
        var lineNumberBackgroundColor: CGColor {
            switch self {
            case .light: 
                return CGColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0)
            case .github: 
                return CGColor(red: 0.94, green: 0.94, blue: 0.94, alpha: 1.0)
            case .dark: 
                return CGColor(red: 0.18, green: 0.2, blue: 0.22, alpha: 1.0)
            case .monokai: 
                return CGColor(red: 0.15, green: 0.16, blue: 0.14, alpha: 1.0)
            case .solarizedLight: 
                return CGColor(red: 0.92, green: 0.9, blue: 0.83, alpha: 1.0)
            }
        }
        
        var headerTextColor: NSColor {
            switch self {
            case .light, .github, .solarizedLight: return NSColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0)
            case .dark, .monokai: return NSColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1.0)
            }
        }
        
        var borderColor: CGColor {
            switch self {
            case .light, .github, .solarizedLight: 
                return CGColor(red: 0.8, green: 0.8, blue: 0.8, alpha: 1.0)
            case .dark: 
                return CGColor(red: 0.3, green: 0.3, blue: 0.35, alpha: 1.0)
            case .monokai: 
                return CGColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 1.0)
            }
        }
    }
    
    // Language mappings for syntax highlighting
    private let languageMap: [String: String] = [
        "swift": "swift",
        "js": "javascript",
        "ts": "typescript",
        "jsx": "javascript",
        "tsx": "typescript",
        "html": "html",
        "css": "css",
        "scss": "scss",
        "less": "less",
        "py": "python",
        "rb": "ruby",
        "java": "java",
        "go": "go",
        "rs": "rust",
        "php": "php",
        "c": "c",
        "cpp": "cpp",
        "cs": "csharp",
        "json": "json",
        "xml": "xml",
        "yaml": "yaml",
        "yml": "yaml",
        "md": "markdown",
        "sh": "bash",
        "bash": "bash",
        "zsh": "bash",
        "sql": "sql",
        "graphql": "graphql",
        "kt": "kotlin",
        "scala": "scala"
    ]
    
    // Find appropriate language for a file
    private func languageForFile(_ file: URL) -> String? {
        let ext = file.pathExtension.lowercased()
        return languageMap[ext]
    }
    
    let supportedTypes = [
        // Code files
        "swift", "ts", "js", "html", "css", "jsx", "tsx", "vue", "php",
        "py", "rb", "java", "cpp", "c", "h", "cs", "go", "rs", "kt",
        "scala", "m", "mm", "pl", "sh", "bash", "zsh", "sql", "r",
        
        // Data files
        "json", "yaml", "yml", "xml", "csv", "toml",
        
        // Documentation
        "md", "mdx", "txt", "rtf", "tex", "doc", "docx", "rst", "adoc", 
        "org", "wiki", "textile", "pod", "markdown", "mdown", "mkdn", "mkd",
        
        // Config files
        "ini", "conf", "config", "env", "gitignore", "dockerignore",
        "eslintrc", "prettierrc", "babelrc", "editorconfig",
        
        // Web files
        "scss", "sass", "less", "svg", "graphql", "wasm", "astro",
        "svelte", "postcss", "prisma", "proto", "hbs", "ejs", "pug",
        
        // Images (for PDF mode)
        "pdf", "jpg", "jpeg", "png", "gif", "heic", "tiff", "webp",
        
        // Office Documents
        "doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp",
        
        // Publishing
        "epub", "pages", "numbers", "key", "indd", "ai",
        
        // Rich Text
        "rtf", "rtfd", "wpd", "odf", "latex",
        
        // Technical Documentation
        "dita", "ditamap", "docbook", "tei", "asciidoc",
        
        // Code Documentation
        "javadoc", "jsdoc", "pdoc", "rdoc", "yard",
        
        // Notebook formats
        "ipynb", "rmd", "qmd"
    ]
    
    private let maxFileSize: Int64 = 500 * 1024 * 1024 // 500MB limit
    private let chunkSize = 1024 * 1024 // 1MB chunks for processing
    
    init() {
        // Set up highlighter theme
        highlighter?.setTheme(to: "atom-one-dark")
    }
    
    func processFiles(mode: ContentView.Mode) {
        currentMode = mode
        isProcessing = true
        error = nil
        progress = 0
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let sortedFiles = self.files.sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            // Build file tree
            self.buildFileTree(from: sortedFiles)
            
            // Validate files
            for url in sortedFiles {
                if !self.validateFile(url) { return }
            }
            
            switch mode {
            case .prompt:
                self.processFilesForPrompt(sortedFiles)
            case .pdf:
                self.processFilesForPDF(sortedFiles)
            }
        }
    }
    
    private func buildFileTree(from files: [URL]) {
        // Group files by their parent directories
        var rootDirectories: [URL: [URL]] = [:]
        
        for fileURL in files {
            let directory = fileURL.deletingLastPathComponent()
            if rootDirectories[directory] == nil {
                rootDirectories[directory] = []
            }
            rootDirectories[directory]?.append(fileURL)
        }
        
        // If we have files from different directories, create a virtual root
        if rootDirectories.count > 1 {
            let root = FileNode(name: "Project", type: .directory, url: nil)
            
            for (directory, directoryFiles) in rootDirectories {
                let dirNode = FileNode(name: directory.lastPathComponent, type: .directory, url: directory)
                
                for fileURL in directoryFiles {
                    let fileNode = FileNode(name: fileURL.lastPathComponent, type: .file, url: fileURL)
                    dirNode.children.append(fileNode)
                }
                
                dirNode.children.sort { $0.name < $1.name }
                root.children.append(dirNode)
            }
            
            root.children.sort { $0.name < $1.name }
            DispatchQueue.main.async {
                self.fileTree = root
            }
        } 
        // If all files come from the same directory
        else if let (directory, directoryFiles) = rootDirectories.first {
            let root = FileNode(name: directory.lastPathComponent, type: .directory, url: directory)
            
            for fileURL in directoryFiles {
                let fileNode = FileNode(name: fileURL.lastPathComponent, type: .file, url: fileURL)
                root.children.append(fileNode)
            }
            
            root.children.sort { $0.name < $1.name }
            DispatchQueue.main.async {
                self.fileTree = root
            }
        }
    }
    
    private func processFilesForPrompt(_ files: [URL]) {
        var result = ""
        let attributedResult = NSMutableAttributedString()
        let totalFiles = Double(files.count)
        
        // Title attributes for attributed string
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor
        ]
        
        let subtitleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        
        // Add file tree to prompt if enabled
        if includeFileTree, let fileTree = fileTree {
            let fileTreeTitle = "# File Structure\n"
            result += fileTreeTitle
            
            let attrFileTreeTitle = NSAttributedString(string: fileTreeTitle, attributes: titleAttributes)
            attributedResult.append(attrFileTreeTitle)
            
            let fileTreeString = generateFileTreeString(node: fileTree, level: 0)
            result += fileTreeString
            
            let attrFileTreeString = NSAttributedString(string: fileTreeString, attributes: subtitleAttributes)
            attributedResult.append(attrFileTreeString)
            
            let filesTitle = "\n\n# Files\n"
            result += filesTitle
            
            let attrFilesTitle = NSAttributedString(string: filesTitle, attributes: titleAttributes)
            attributedResult.append(attrFilesTitle)
        }
        
        for (index, url) in files.enumerated() {
            autoreleasepool {
                // Update progress more frequently
                DispatchQueue.main.async {
                    self.progress = Double(index) / totalFiles
                }
                
                let fileContent: String
                let filename = url.lastPathComponent
                let fileExtension = url.pathExtension.lowercased()
                
                do {
                    if fileExtension == "pdf" {
                        if let pdf = PDFDocument(url: url),
                           let text = pdf.string {
                            fileContent = text
                        } else {
                            fileContent = "[PDF content could not be extracted]"
                        }
                    } else {
                        fileContent = try String(contentsOf: url, encoding: .utf8)
                    }
                    
                    // Format the output based on selected format
                    switch promptFormat {
                    case .standard:
                        let fileHeader = "<\(filename)>\n"
                        let fileFooter = "\n</\(filename)>\n\n"
                        
                        result += fileHeader + fileContent + fileFooter
                        
                        // Create attributed version
                        let headerAttr = NSAttributedString(string: fileHeader, attributes: titleAttributes)
                        attributedResult.append(headerAttr)
                        
                        // Apply syntax highlighting if enabled
                        if let language = languageForFile(url), useSyntaxHighlighting {
                            if let highlighted = highlighter?.highlight(fileContent, as: language) {
                                attributedResult.append(highlighted)
                            } else {
                                let contentAttr = NSAttributedString(string: fileContent, attributes: [
                                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                                ])
                                attributedResult.append(contentAttr)
                            }
                        } else {
                            let contentAttr = NSAttributedString(string: fileContent, attributes: [
                                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                            ])
                            attributedResult.append(contentAttr)
                        }
                        
                        let footerAttr = NSAttributedString(string: fileFooter, attributes: titleAttributes)
                        attributedResult.append(footerAttr)
                        
                    case .fileTree:
                        let fileHeader = "<\(filename)>\n"
                        let fileFooter = "\n</\(filename)>\n\n"
                        
                        result += fileHeader + fileContent + fileFooter
                        
                        // Create attributed version
                        let headerAttr = NSAttributedString(string: fileHeader, attributes: titleAttributes)
                        attributedResult.append(headerAttr)
                        
                        // Apply syntax highlighting if enabled
                        if let language = languageForFile(url), useSyntaxHighlighting {
                            if let highlighted = highlighter?.highlight(fileContent, as: language) {
                                attributedResult.append(highlighted)
                            } else {
                                let contentAttr = NSAttributedString(string: fileContent, attributes: [
                                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                                ])
                                attributedResult.append(contentAttr)
                            }
                        } else {
                            let contentAttr = NSAttributedString(string: fileContent, attributes: [
                                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                            ])
                            attributedResult.append(contentAttr)
                        }
                        
                        let footerAttr = NSAttributedString(string: fileFooter, attributes: titleAttributes)
                        attributedResult.append(footerAttr)
                        
                    case .markdown:
                        let mdHeader = "## \(filename)\n\n```\(fileExtension)\n"
                        let mdFooter = "\n```\n\n"
                        
                        result += mdHeader + fileContent + mdFooter
                        
                        // Create attributed version with markdown styling
                        let headerAttr = NSAttributedString(string: mdHeader, attributes: titleAttributes)
                        attributedResult.append(headerAttr)
                        
                        // Apply syntax highlighting if enabled
                        if let language = languageForFile(url), useSyntaxHighlighting {
                            if let highlighted = highlighter?.highlight(fileContent, as: language) {
                                attributedResult.append(highlighted)
                            } else {
                                let contentAttr = NSAttributedString(string: fileContent, attributes: [
                                    .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                                ])
                                attributedResult.append(contentAttr)
                            }
                        } else {
                            let contentAttr = NSAttributedString(string: fileContent, attributes: [
                                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                            ])
                            attributedResult.append(contentAttr)
                        }
                        
                        let footerAttr = NSAttributedString(string: mdFooter, attributes: titleAttributes)
                        attributedResult.append(footerAttr)
                    }
                    
                    // Final progress update
                    DispatchQueue.main.async {
                        self.progress = Double(index + 1) / totalFiles
                    }
                } catch {
                    logger.error("Error processing file: \(error.localizedDescription)")
                }
            }
        }
        
        DispatchQueue.main.async {
            self.processedContent = result
            self.processedAttributedContent = attributedResult
            self.progress = 1.0
            self.isProcessing = false
        }
    }
    
    private func generateFileTreeString(node: FileNode, level: Int) -> String {
        let indent = String(repeating: "  ", count: level)
        var result = "\(indent)"
        
        if node.type == .directory {
            result += "📁 \(node.name)/\n"
            for child in node.children {
                result += generateFileTreeString(node: child, level: level + 1)
            }
        } else {
            result += "📄 \(node.name)\n"
        }
        
        return result
    }
    
    private func processFilesForPDF(_ files: [URL]) {
        let pdfDocument = PDFDocument()
        let totalFiles = Double(files.count)
        
        // Add file tree if enabled
        if includeFileTree, let fileTree = fileTree {
            if let fileTreePage = createFileTreePage(from: fileTree) {
                pdfDocument.insert(fileTreePage, at: pdfDocument.pageCount)
            }
        }
        
        // Ensure proper highlighting theme based on PDF theme
        highlighter?.setTheme(to: pdfTheme.themeName)
        
        for (index, url) in files.enumerated() {
            autoreleasepool {
                // Update progress
                DispatchQueue.main.async {
                    self.progress = Double(index) / totalFiles
                }
                
                do {
                    switch url.pathExtension.lowercased() {
                    case "pdf":
                        if let existingPDF = PDFDocument(url: url) {
                            // Add document title page with filename
                            if let titlePage = createTitlePage(for: url.lastPathComponent) {
                                pdfDocument.insert(titlePage, at: pdfDocument.pageCount)
                            }
                            
                            // Add each page from the existing PDF
                            for i in 0..<existingPDF.pageCount {
                                if let page = existingPDF.page(at: i) {
                                    pdfDocument.insert(page, at: pdfDocument.pageCount)
                                }
                            }
                        } else {
                            throw NSError(domain: "PDFProcessingError", code: 1, userInfo: [
                                NSLocalizedDescriptionKey: "Failed to read PDF: \(url.lastPathComponent)"
                            ])
                        }
                        
                    case "jpg", "jpeg", "png", "gif", "heic", "tiff", "webp":
                        if let image = NSImage(contentsOf: url),
                           let titlePage = createTitlePage(for: url.lastPathComponent),
                           let page = createPDFPage(from: image) {
                            pdfDocument.insert(titlePage, at: pdfDocument.pageCount)
                            pdfDocument.insert(page, at: pdfDocument.pageCount)
                        } else {
                            throw NSError(domain: "ImageProcessingError", code: 2, userInfo: [
                                NSLocalizedDescriptionKey: "Failed to process image: \(url.lastPathComponent)"
                            ])
                        }
                        
                    default:
                        if let titlePage = createTitlePage(for: url.lastPathComponent) {
                            pdfDocument.insert(titlePage, at: pdfDocument.pageCount)
                            
                            // For code files, use syntax highlighted version if possible
                            if let language = languageForFile(url), useSyntaxHighlighting {
                                if let pages = createSyntaxHighlightedPages(from: url, language: language) {
                                    for page in pages {
                                        pdfDocument.insert(page, at: pdfDocument.pageCount)
                                    }
                                } else if let textPage = createPDFPage(from: url) {
                                    pdfDocument.insert(textPage, at: pdfDocument.pageCount)
                                } else {
                                    throw NSError(domain: "FileProcessingError", code: 3, userInfo: [
                                        NSLocalizedDescriptionKey: "Failed to create PDF pages for: \(url.lastPathComponent)"
                                    ])
                                }
                            } else if let textPage = createPDFPage(from: url) {
                                pdfDocument.insert(textPage, at: pdfDocument.pageCount)
                            } else {
                                throw NSError(domain: "FileProcessingError", code: 4, userInfo: [
                                    NSLocalizedDescriptionKey: "Failed to create PDF page for: \(url.lastPathComponent)"
                                ])
                            }
                        } else {
                            throw NSError(domain: "TitlePageError", code: 5, userInfo: [
                                NSLocalizedDescriptionKey: "Failed to create title page for: \(url.lastPathComponent)"
                            ])
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self.progress = Double(index + 1) / totalFiles
                    }
                } catch {
                    logger.error("Error processing file for PDF: \(error.localizedDescription)")
                }
            }
        }
        
        // Add table of contents at the beginning if we have multiple files
        if files.count > 1 {
            if let tocPage = createTableOfContents(for: files) {
                pdfDocument.insert(tocPage, at: 0)
            }
        }
        
        DispatchQueue.main.async {
            self.processedPDF = pdfDocument
            self.progress = 1.0
            self.isProcessing = false
        }
    }
    
    private func createTableOfContents(for files: [URL]) -> PDFPage? {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let pdfData = NSMutableData()
        
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return nil }
        
        var mediaBox = CGRect(origin: .zero, size: pageRect.size)
        
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }
        
        // Start PDF page
        context.beginPage(mediaBox: &mediaBox)
        
        // Fill white background
        context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
        context.fill(mediaBox)
        
        // Draw title
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        
        let title = "Table of Contents"
        let titleString = NSAttributedString(string: title, attributes: titleAttributes)
        let titleRect = CGRect(x: 72, y: 720, width: pageRect.width - 144, height: 30)
        titleString.draw(in: titleRect)
        
        // Draw separator line
        context.setStrokeColor(CGColor(gray: 0.8, alpha: 1.0))
        context.setLineWidth(1.0)
        context.move(to: CGPoint(x: 72, y: 710))
        context.addLine(to: CGPoint(x: pageRect.width - 72, y: 710))
        context.strokePath()
        
        // Draw file list
        let fileAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor.black
        ]
        
        var yPosition: CGFloat = 680
        
        for (index, url) in files.enumerated() {
            let fileEntry = "\(index + 1). \(url.lastPathComponent)"
            let fileString = NSAttributedString(string: fileEntry, attributes: fileAttributes)
            let fileRect = CGRect(x: 72, y: yPosition, width: pageRect.width - 144, height: 20)
            fileString.draw(in: fileRect)
            
            yPosition -= 25
            
            // Start a new page if we run out of space
            if yPosition < 72 && index < files.count - 1 {
                context.endPage()
                context.beginPage(mediaBox: &mediaBox)
                
                // Fill white background for new page
                context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
                context.fill(mediaBox)
                
                yPosition = 720
            }
        }
        
        context.endPage()
        context.closePDF()
        
        guard let pdfDocument = PDFDocument(data: pdfData as Data) else { return nil }
        return pdfDocument.page(at: 0)
    }
    
    private func createTitlePage(for filename: String) -> PDFPage? {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let pdfData = NSMutableData()
        
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return nil }
        
        var mediaBox = CGRect(origin: .zero, size: pageRect.size)
        
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }
        
        // Start PDF page
        context.beginPage(mediaBox: &mediaBox)
        
        // Fill white background
        context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
        context.fill(mediaBox)
        
        // Draw a subtle header decoration
        let gradientColors = [
            CGColor(red: 0.9, green: 0.9, blue: 0.95, alpha: 1.0),
            CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
        ]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors as CFArray, locations: [0, 1])!
        
        context.saveGState()
        context.addRect(CGRect(x: 0, y: 742, width: 612, height: 50))
        context.clip()
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 742), end: CGPoint(x: 0, y: 792), options: [])
        context.restoreGState()
        
        // Create attributes for title text
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        
        // Draw filename as title
        let titleString = NSAttributedString(string: filename, attributes: titleAttributes)
        
        // Center the text
        let titleSize = titleString.size()
        let centeredTitleRect = CGRect(
            x: (pageRect.width - titleSize.width) / 2,
            y: 396,
            width: titleSize.width,
            height: titleSize.height
        )
        
        titleString.draw(in: centeredTitleRect)
        
        // Add a decorative line
        context.setStrokeColor(CGColor(gray: 0.8, alpha: 1.0))
        context.setLineWidth(1.0)
        context.move(to: CGPoint(x: (pageRect.width - 200) / 2, y: 380))
        context.addLine(to: CGPoint(x: (pageRect.width + 200) / 2, y: 380))
        context.strokePath()
        
        // Add date at the bottom
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        let dateString = "Generated on " + dateFormatter.string(from: Date())
        
        let dateAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.darkGray
        ]
        
        let dateAttrString = NSAttributedString(string: dateString, attributes: dateAttributes)
        let dateSize = dateAttrString.size()
        let dateRect = CGRect(
            x: (pageRect.width - dateSize.width) / 2,
            y: 100,
            width: dateSize.width,
            height: dateSize.height
        )
        
        dateAttrString.draw(in: dateRect)
        
        context.endPage()
        context.closePDF()
        
        guard let pdfDocument = PDFDocument(data: pdfData as Data) else { return nil }
        return pdfDocument.page(at: 0)
    }
    
    private func createPDFPage(from image: NSImage) -> PDFPage? {
        let imageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let pdfData = NSMutableData()
        
        guard let context = CGContext(consumer: CGDataConsumer(data: pdfData as CFMutableData)!,
                                    mediaBox: nil,
                                    nil) else { return nil }
        
        context.beginPDFPage(nil)
        
        // Calculate aspect ratio preserving dimensions
        let imageSize = image.size
        let scale = min(imageRect.width / imageSize.width,
                       imageRect.height / imageSize.height)
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        let x = (imageRect.width - scaledWidth) / 2
        let y = (imageRect.height - scaledHeight) / 2
        
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.draw(cgImage, in: CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight))
        }
        
        context.endPDFPage()
        context.closePDF()
        
        guard let pdfDocument = PDFDocument(data: pdfData as Data) else { return nil }
        return pdfDocument.page(at: 0)
    }
    
    private func createSyntaxHighlightedPages(from url: URL, language: String) -> [PDFPage]? {
        do {
            // Read file content
            let content = try String(contentsOf: url, encoding: .utf8)
            
            // Set theme for PDF visibility
            highlighter?.setTheme(to: pdfTheme.themeName)
            
            // Highlight the code with selected theme
            var highlightedCode: NSMutableAttributedString
            if let highlighted = highlighter?.highlight(content, as: language) {
                highlightedCode = NSMutableAttributedString(attributedString: highlighted)
                
                // Ensure text color is appropriate for the theme
                highlightedCode.addAttributes([
                    .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                    .foregroundColor: pdfTheme.textColor
                ], range: NSRange(location: 0, length: highlightedCode.length))
            } else {
                // Fallback if highlighting fails
                highlightedCode = NSMutableAttributedString(string: content)
                highlightedCode.addAttributes([
                    .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                    .foregroundColor: pdfTheme.textColor
                ], range: NSRange(location: 0, length: highlightedCode.length))
            }
            
            // Add line numbers
            let codeLinesArray = content.components(separatedBy: .newlines)
            let lineNumberAttrString = NSMutableAttributedString()
            let lineAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: pdfTheme.lineNumberColor
            ]
            
            // Create line numbers
            for i in 1...codeLinesArray.count {
                let lineNumberStr = "\(i)".padding(toLength: 4, withPad: " ", startingAt: 0)
                let lineAttr = NSAttributedString(string: "\(lineNumberStr) ", attributes: lineAttrs)
                lineNumberAttrString.append(lineAttr)
                if i < codeLinesArray.count {
                    lineNumberAttrString.append(NSAttributedString(string: "\n"))
                }
            }
            
            // Create PDF pages
            return createPDFPagesFromAttributedCode(highlightedCode, lineNumbers: lineNumberAttrString, fileName: url.lastPathComponent)
            
        } catch {
            logger.error("Error creating syntax highlighted pages: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func createPDFPagesFromAttributedCode(_ codeAttr: NSAttributedString, lineNumbers: NSAttributedString, fileName: String) -> [PDFPage]? {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let maxContentHeight = 700.0 // Leave margin
        
        // Create framesetter for code
        let codeSetter = CTFramesetterCreateWithAttributedString(codeAttr)
        
        // Determine how many pages we need
        let contentRect = CGRect(x: 120, y: 50, width: pageRect.width - 170, height: maxContentHeight)
        let totalContentHeight = CTFramesetterSuggestFrameSizeWithConstraints(codeSetter, CFRange(location: 0, length: 0), nil, CGSize(width: contentRect.width, height: CGFloat.greatestFiniteMagnitude), nil).height
        
        let pagesNeeded = max(1, Int(ceil(totalContentHeight / maxContentHeight)))
        var pages: [PDFPage] = []
        
        var textPosition = 0
        
        // Create each page
        for pageIndex in 0..<pagesNeeded {
            let pdfData = NSMutableData()
            guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { continue }
            
            var mediaBox = CGRect(origin: .zero, size: pageRect.size)
            
            guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
                continue
            }
            
            // Start PDF page
            context.beginPage(mediaBox: &mediaBox)
            
            // Fill background color based on theme
            context.setFillColor(pdfTheme.backgroundColor)
            context.fill(mediaBox)
            
            // Draw a subtle header
            let headerHeight: CGFloat = 36
            let headerRect = CGRect(x: 0, y: pageRect.height - headerHeight, width: pageRect.width, height: headerHeight)
            
            // Draw subtle header gradient
            let headerGradientColors = pdfTheme.headerBackgroundColors
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let headerGradient = CGGradient(colorsSpace: colorSpace, colors: headerGradientColors as CFArray, locations: [0, 1])!
            
            context.saveGState()
            context.addRect(headerRect)
            context.clip()
            context.drawLinearGradient(headerGradient, start: CGPoint(x: 0, y: headerRect.maxY), end: CGPoint(x: 0, y: headerRect.minY), options: [])
            context.restoreGState()
            
            // Draw thin separator line
            context.setStrokeColor(pdfTheme.borderColor)
            context.setLineWidth(0.5)
            context.move(to: CGPoint(x: 0, y: pageRect.height - headerHeight))
            context.addLine(to: CGPoint(x: pageRect.width, y: pageRect.height - headerHeight))
            context.strokePath()
            
            // Draw header text
            let headerAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: pdfTheme.headerTextColor
            ]
            
            let headerText = "\(fileName) - Page \(pageIndex + 1) of \(pagesNeeded)"
            let headerString = NSAttributedString(string: headerText, attributes: headerAttributes)
            
            let headerTextRect = CGRect(x: 60, y: pageRect.height - 24, width: pageRect.width - 120, height: 20)
            headerString.draw(in: headerTextRect)
            
            // Draw code container with subtle border
            let codeRect = CGRect(x: 60, y: 40, width: pageRect.width - 120, height: maxContentHeight - 60)
            
            // Draw code background
            context.setFillColor(pdfTheme.codeBackgroundColor)
            let codeRoundedRect = CGPath(roundedRect: codeRect, cornerWidth: 6, cornerHeight: 6, transform: nil)
            context.addPath(codeRoundedRect)
            context.fillPath()
            
            // Draw subtle border
            context.setStrokeColor(pdfTheme.borderColor)
            context.setLineWidth(0.5)
            context.addPath(codeRoundedRect)
            context.strokePath()
            
            // Line numbers column 
            let lineNumbersRect = CGRect(x: 70, y: 50, width: 40, height: maxContentHeight - 80)
            context.setFillColor(pdfTheme.lineNumberBackgroundColor)
            context.fill(lineNumbersRect)
            
            // Save graphics state before drawing text
            context.saveGState()
            
            // Fix for upside-down text: 
            // First translate to the bottom of where we want to draw text
            context.translateBy(x: 0, y: pageRect.height - 50)
            // Then apply the standard flip transformation
            context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            
            // Create frame for line numbers
            let lineNumbersPath = CGPath(rect: CGRect(x: 70, y: -maxContentHeight + 80, width: 40, height: maxContentHeight - 80), transform: nil)
            let lineNumberSetter = CTFramesetterCreateWithAttributedString(lineNumbers)
            let lineNumberFrame = CTFramesetterCreateFrame(lineNumberSetter, CFRange(location: 0, length: 0), lineNumbersPath, nil)
            
            // Draw line numbers
            CTFrameDraw(lineNumberFrame, context)
            
            // Create frame for code with proper offset for line numbers
            let codeTextPath = CGPath(rect: CGRect(x: 120, y: -maxContentHeight + 80, width: pageRect.width - 170, height: maxContentHeight - 80), transform: nil)
            
            let frameLength = min(codeAttr.length - textPosition, codeAttr.length)
            let frame = CTFramesetterCreateFrame(codeSetter, CFRange(location: textPosition, length: frameLength), codeTextPath, nil)
            
            // Draw code
            CTFrameDraw(frame, context)
            
            // Restore graphics state
            context.restoreGState()
            
            // Determine how much text was used
            let frameRange = CTFrameGetVisibleStringRange(frame)
            textPosition += frameRange.length
            
            context.endPage()
            context.closePDF()
            
            if let pdfPage = PDFDocument(data: pdfData as Data)?.page(at: 0) {
                pages.append(pdfPage)
            }
            
            // If we've used all the text, exit the loop
            if textPosition >= codeAttr.length {
                break
            }
        }
        
        return pages
    }
    
    private func createPDFPage(from url: URL) -> PDFPage? {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            
            // Check if we should use syntax highlighting
            let language = languageForFile(url)
            let attributedString: NSAttributedString
            
            if let language = language, useSyntaxHighlighting {
                // Use the selected theme
                highlighter?.setTheme(to: pdfTheme.themeName)
                
                if let highlighted = highlighter?.highlight(content, as: language) {
                    // Create mutable copy to ensure proper styling
                    let mutableHighlighted = NSMutableAttributedString(attributedString: highlighted)
                    
                    // Apply theme-appropriate text color
                    mutableHighlighted.addAttributes([
                        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                        .foregroundColor: pdfTheme.textColor
                    ], range: NSRange(location: 0, length: mutableHighlighted.length))
                    
                    attributedString = mutableHighlighted
                } else {
                    // Create regular attributed string with improved formatting
                    let style = NSMutableParagraphStyle()
                    style.lineSpacing = 2
                    style.paragraphSpacing = 6
                    
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                        .foregroundColor: pdfTheme.textColor,
                        .paragraphStyle: style
                    ]
                    
                    attributedString = NSAttributedString(string: content, attributes: attributes)
                }
            } else {
                // Create regular attributed string with improved formatting
                let style = NSMutableParagraphStyle()
                style.lineSpacing = 2
                style.paragraphSpacing = 6
                
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: pdfTheme.textColor,
                    .paragraphStyle: style
                ]
                
                attributedString = NSAttributedString(string: content, attributes: attributes)
            }
            
            // Create PDF page with modern styling
            let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
            let pdfData = NSMutableData()
            
            guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return nil }
            
            var mediaBox = CGRect(origin: .zero, size: pageRect.size)
            guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
                return nil
            }
            
            // Start PDF page
            context.beginPage(mediaBox: &mediaBox)
            
            // Fill background color based on theme
            context.setFillColor(pdfTheme.backgroundColor)
            context.fill(mediaBox)
            
            // Draw a modern header with subtle gradient
            let headerHeight: CGFloat = 36
            let headerRect = CGRect(x: 0, y: pageRect.height - headerHeight, width: pageRect.width, height: headerHeight)
            
            // Create header gradient
            let headerGradientColors = pdfTheme.headerBackgroundColors
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let headerGradient = CGGradient(colorsSpace: colorSpace, colors: headerGradientColors as CFArray, locations: [0, 1])!
            
            // Draw header background
            context.saveGState()
            context.addRect(headerRect)
            context.clip()
            context.drawLinearGradient(headerGradient, start: CGPoint(x: 0, y: headerRect.maxY), end: CGPoint(x: 0, y: headerRect.minY), options: [])
            context.restoreGState()
            
            // Draw separator line
            context.setStrokeColor(pdfTheme.borderColor)
            context.setLineWidth(0.5)
            context.move(to: CGPoint(x: 0, y: pageRect.height - headerHeight))
            context.addLine(to: CGPoint(x: pageRect.width, y: pageRect.height - headerHeight))
            context.strokePath()
            
            // Draw header text
            let headerAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: pdfTheme.headerTextColor
            ]
            
            let headerText = url.lastPathComponent
            let headerString = NSAttributedString(string: headerText, attributes: headerAttributes)
            let headerTextRect = CGRect(x: 50, y: pageRect.height - 24, width: pageRect.width - 100, height: 20)
            headerString.draw(in: headerTextRect)
            
            // Draw content with line numbers
            let contentRect = CGRect(x: 60, y: 40, width: pageRect.width - 120, height: pageRect.height - headerHeight - 60)
            
            // Draw content background
            context.setFillColor(pdfTheme.codeBackgroundColor)
            context.addPath(CGPath(roundedRect: contentRect, cornerWidth: 6, cornerHeight: 6, transform: nil))
            context.fillPath()
            
            // Draw subtle border
            context.setStrokeColor(pdfTheme.borderColor)
            context.setLineWidth(0.5)
            context.addPath(CGPath(roundedRect: contentRect, cornerWidth: 6, cornerHeight: 6, transform: nil))
            context.strokePath()
            
            // Add line numbers to left margin
            let lines = content.components(separatedBy: .newlines)
            var lineNumbersText = ""
            for i in 1...min(lines.count, 1000) { // Limit to 1000 lines for performance
                lineNumbersText += "\(i)\n"
            }
            
            // Create line numbers
            let lineNumbersAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
                .foregroundColor: pdfTheme.lineNumberColor
            ]
            
            // Draw line numbers background
            let lineNumbersRect = CGRect(x: 70, y: 50, width: 30, height: pageRect.height - headerHeight - 80)
            context.setFillColor(pdfTheme.lineNumberBackgroundColor)
            context.fill(lineNumbersRect)
            
            // Save state before drawing text
            context.saveGState()
            
            // Fix for upside-down text:
            // First translate to the bottom of where we want to draw text
            context.translateBy(x: 0, y: pageRect.height - 50)
            // Then apply the standard flip transformation
            context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            
            // Create the line numbers attributed string
            let lineNumbersString = NSAttributedString(string: lineNumbersText, attributes: lineNumbersAttributes)
            
            // Create line numbers frame with adjusted coordinates
            let lineNumbersPath = CGPath(rect: CGRect(x: 70, y: -lineNumbersRect.height, width: 30, height: lineNumbersRect.height), transform: nil)
            let lineNumbersFramesetter = CTFramesetterCreateWithAttributedString(lineNumbersString)
            let lineNumbersFrame = CTFramesetterCreateFrame(lineNumbersFramesetter, CFRange(location: 0, length: 0), lineNumbersPath, nil)
            
            // Draw line numbers
            CTFrameDraw(lineNumbersFrame, context)
            
            // Create content frame with inset to make room for line numbers and adjusted coordinates
            let textContentRect = CGRect(x: 110, y: -(pageRect.height - headerHeight - 80), width: pageRect.width - 170, height: pageRect.height - headerHeight - 80)
            
            // Create content frame
            let path = CGPath(rect: textContentRect, transform: nil)
            let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attributedString.length), path, nil)
            
            // Draw content
            CTFrameDraw(frame, context)
            
            // Restore state
            context.restoreGState()
            
            context.endPage()
            context.closePDF()
            
            guard let pdfDocument = PDFDocument(data: pdfData as Data) else { return nil }
            return pdfDocument.page(at: 0)
        } catch {
            logger.error("Error creating PDF page: \(error.localizedDescription)")
            return nil
        }
    }
    
    func clearFiles() {
        files = []
        processedContent = ""
        processedAttributedContent = nil
        processedPDF = nil
        error = nil
    }
    
    func setMode(_ mode: ContentView.Mode) {
        if currentMode != mode && !files.isEmpty {
            lastProcessedFiles = files
            currentMode = mode
            processFiles(mode: mode)
        } else {
            currentMode = mode
        }
    }
    
    private func validateFile(_ url: URL) -> Bool {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            
            if fileSize > maxFileSize {
                DispatchQueue.main.async {
                    self.error = "File too large: \(url.lastPathComponent)"
                    self.isProcessing = false
                }
                return false
            }
            return true
        } catch {
            logger.error("Error accessing file: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.error = "Error accessing file: \(url.lastPathComponent)"
                self.isProcessing = false
            }
            return false
        }
    }
    
    // Add a new method to create file tree page
    private func createFileTreePage(from node: FileNode) -> PDFPage? {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let pdfData = NSMutableData()
        
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return nil }
        
        var mediaBox = CGRect(origin: .zero, size: pageRect.size)
        
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }
        
        // Start PDF page
        context.beginPage(mediaBox: &mediaBox)
        
        // Fill white background
        context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
        context.fill(mediaBox)
        
        // Draw header
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
            .foregroundColor: NSColor.black
        ]
        
        let title = "File Structure"
        let titleString = NSAttributedString(string: title, attributes: titleAttributes)
        let titleRect = CGRect(x: 72, y: 720, width: pageRect.width - 144, height: 36)
        titleString.draw(in: titleRect)
        
        // Draw separator line
        context.setStrokeColor(CGColor(gray: 0.8, alpha: 1.0))
        context.setLineWidth(1.0)
        context.move(to: CGPoint(x: 72, y: 710))
        context.addLine(to: CGPoint(x: pageRect.width - 72, y: 710))
        context.strokePath()
        
        // Generate file tree text
        let fileTreeString = generateFileTreeString(node: node, level: 0)
        
        // Draw file tree with monospaced font
        let treeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: NSColor.black
        ]
        
        let treeAttrString = NSAttributedString(string: fileTreeString, attributes: treeAttributes)
        let treeRect = CGRect(x: 72, y: 100, width: pageRect.width - 144, height: 600)
        treeAttrString.draw(in: treeRect)
        
        context.endPage()
        context.closePDF()
        
        guard let pdfDocument = PDFDocument(data: pdfData as Data) else { return nil }
        return pdfDocument.page(at: 0)
    }
}

class FileNode: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var type: NodeType
    var url: URL?
    var children: [FileNode] = []
    
    enum NodeType {
        case directory
        case file
    }
    
    init(name: String, type: NodeType, url: URL?) {
        self.name = name
        self.type = type
        self.url = url
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.id == rhs.id
    }
} 
