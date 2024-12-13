import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import os
import AppKit

private let logger = Logger(subsystem: "me.nuanc.Uno", category: "FileProcessor")

class FileProcessor: ObservableObject {
    @Published var files: [URL] = [] {
        didSet {
            if !files.isEmpty {
                processFiles(mode: currentMode)
            } else {
                processedContent = ""
                processedPDF = nil
            }
        }
    }
    @Published private(set) var currentMode: ContentView.Mode = .prompt
    @Published var isProcessing = false
    @Published var processedContent: String = ""
    @Published var processedPDF: PDFDocument?
    @Published var error: String?
    @Published var progress: Double = 0
    @Published var includeTreeStructure: Bool = false
    @Published private(set) var lastProcessedFiles: [URL] = []
    @Published var includeTreeInPrompt = false

    private let processingQueue = DispatchQueue(label: "me.nuanc.Uno.processing", qos: .userInitiated, attributes: .concurrent)
    private let progressQueue = DispatchQueue(label: "me.nuanc.Uno.progress")
    private let maxConcurrentOperations = 4
    
    let supportedTypes = [
        // Code files
        "swift", "ts", "js", "html", "css", "jsx", "tsx", "vue", "php",
        "py", "rb", "java", "cpp", "c", "h", "cs", "go", "rs", "kt",
        "scala", "m", "mm", "pl", "sh", "bash", "zsh", "sql", "r",
        
        // Project files
        "xcodeproj", "xcworkspace", "project", "workspace", "sln",
        "idea", "vscode", "sublime-project",
        
        // Build files
        "gradle", "maven", "pom", "bazel", "buck", "make", "cmake",
        "rakefile", "gemfile", "podfile", "fastfile",
        
        // Lock files
        "lock", "package-lock.json", "yarn.lock", "gemfile.lock",
        "podfile.lock", "composer.lock",
        
        // Data files
        "json", "yaml", "yml", "xml", "csv", "toml", "properties",
        "cfg", "conf", "config", "settings", "ini", "env",
        
        // Documentation
        "md", "mdx", "txt", "rtf", "tex", "doc", "docx", "rst", "adoc", 
        "org", "wiki", "textile", "pod", "markdown", "mdown", "mkdn", "mkd",
        
        // Config files
        "ini", "conf", "config", "env", "gitignore", "dockerignore",
        "eslintrc", "prettierrc", "babelrc", "editorconfig", "rc",
        
        // Shell
        "fish", "csh", "ksh", "tcsh", "bash_profile", "zshrc", "bashrc",
        
        // Database
        "db", "sqlite", "sqlite3", "sql", "psql", "mysql",
        
        // Web files
        "scss", "sass", "less", "svg", "graphql", "wasm", "astro",
        "svelte", "postcss", "prisma", "proto", "hbs", "ejs", "pug",
        "next", "nuxt", "angular", "vue", "react",
        
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
    
    private let memoryManager = MemoryManager.shared
    private let performanceMonitor = PerformanceMonitor.shared
    
    func processFiles(mode: ContentView.Mode) {
        isProcessing = true
        progress = 0
        
        let totalFiles = Double(files.count)
        
        processingQueue.async {
            for (index, file) in self.files.enumerated() {
                autoreleasepool {
                    self.processFile(file, mode: mode)
                    DispatchQueue.main.async {
                        self.progress = Double(index + 1) / totalFiles
                    }
                }
            }
            
            DispatchQueue.main.async {
                self.isProcessing = false
                self.lastProcessedFiles = self.files
            }
        }
    }
    
    private func processFilesForPrompt(_ files: [URL]) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            let totalFiles = Double(files.count)
            var finalContent = ""
            
            // Add tree structure if enabled
            if self.includeTreeInPrompt {
                do {
                    let rootNodes = try files.map { url -> FolderNode in
                        if (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
                            return try self.buildFolderStructure(url)
                        } else {
                            return FolderNode(url: url)
                        }
                    }
                    
                    finalContent += "# File Structure:\n"
                    for node in rootNodes {
                        finalContent += self.renderTreeStructure(node)
                    }
                    finalContent += "\n# File Contents:\n\n"
                } catch {
                    DispatchQueue.main.async {
                        self.error = "Failed to build file structure: \(error.localizedDescription)"
                        self.isProcessing = false
                    }
                    return
                }
            }
            
            let operationQueue = OperationQueue()
            operationQueue.maxConcurrentOperationCount = self.maxConcurrentOperations
            var results = [(index: Int, content: String)]()
            
            let group = DispatchGroup()
            
            for (index, url) in files.enumerated() {
                group.enter()
                
                operationQueue.addOperation {
                    do {
                        let content = try self.processFileForPrompt(url)
                        results.append((index, content))
                        
                        DispatchQueue.main.async {
                            self.progress = Double(index + 1) / totalFiles
                        }
                        
                        group.leave()
                    } catch {
                        DispatchQueue.main.async {
                            self.error = "Failed to process \(url.lastPathComponent): \(error.localizedDescription)"
                            self.isProcessing = false
                        }
                        group.leave()
                    }
                }
            }
            
            group.notify(queue: .main) {
                // Sort results by original index
                let sortedResults = results.sorted { $0.index < $1.index }
                finalContent += sortedResults.map { $0.content }.joined(separator: "\n\n")
                
                self.processedContent = finalContent
                self.progress = 1.0
                self.isProcessing = false
            }
        }
    }
    
    private func processFilesForPDF(_ files: [URL]) {
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            do {
                let pdfProcessor = PDFProcessor()
                let pdfDocument = try pdfProcessor.createPDF(from: files) { progress in
                    DispatchQueue.main.async {
                        self.progress = progress.totalProgress
                        logger.debug("Processing \(progress.currentFile): \(Int(progress.fileProgress * 100))%")
                    }
                }
                
                // Compress the PDF if it's large
                if let data = pdfDocument.dataRepresentation(),
                   data.count > 10_000_000 { // 10MB
                    if let compressedPDF = try? PDFDocument(data: try self.compressPDF(data)) {
                        DispatchQueue.main.async {
                            self.processedPDF = compressedPDF
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        self.processedPDF = pdfDocument
                    }
                }
                
                DispatchQueue.main.async {
                    self.progress = 1.0
                    self.isProcessing = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = error.localizedDescription
                    self.isProcessing = false
                }
            }
        }
    }
    
    private func compressPDF(_ data: Data) throws -> Data {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        
        do {
            try data.write(to: tempURL)
            
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/gs")
            task.arguments = [
                "-sDEVICE=pdfwrite",
                "-dCompatibilityLevel=1.4",
                "-dPDFSETTINGS=/ebook",
                "-dNOPAUSE",
                "-dQUIET",
                "-dBATCH",
                "-sOutputFile=\(tempURL.path)_compressed",
                tempURL.path
            ]
            
            try task.run()
            task.waitUntilExit()
            
            let compressedData = try Data(contentsOf: URL(fileURLWithPath: tempURL.path + "_compressed"))
            
            try? FileManager.default.removeItem(at: tempURL)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: tempURL.path + "_compressed"))
            
            return compressedData
        } catch {
            throw DocumentError.extractionFailed(reason: "Failed to compress PDF: \(error.localizedDescription)")
        }
    }
    
    private func processChunk(_ files: [URL], into pdfDocument: PDFDocument) {
        for file in files {
            autoreleasepool {
                // Process single file
                if let page = createPDFPage(from: file) {
                    pdfDocument.insert(page, at: pdfDocument.pageCount)
                }
            }
        }
    }
    
    private func createPDFPage(from url: URL) -> PDFPage? {
        // Handle PDF files directly
        if url.pathExtension.lowercased() == "pdf",
           let existingPDF = PDFDocument(url: url),
           let firstPage = existingPDF.page(at: 0) {
            return firstPage
        }
        
        // Handle image files
        if ["jpg", "jpeg", "png", "gif", "heic", "tiff", "webp"].contains(url.pathExtension.lowercased()) {
            if let image = NSImage(contentsOf: url) {
                return createPDFPage(from: image)
            }
            return nil
        }
        
        // Handle text files
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            
            // Create attributed string with improved formatting
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 2
            style.paragraphSpacing = 10
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: style
            ]
            
            let attributedString = NSAttributedString(string: content, attributes: attributes)
            
            // Create PDF page
            let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
            let pdfData = NSMutableData()
            
            // Create a mutable copy of the page rect
            var mediaBox = CGRect(origin: .zero, size: pageRect.size)
            
            guard let context = CGContext(consumer: CGDataConsumer(data: pdfData as CFMutableData)!,
                                        mediaBox: &mediaBox,
                                        nil) else { return nil }
            
            // Use the mutable mediaBox for beginPage
            context.beginPage(mediaBox: &mediaBox)
            
            // Set up the coordinate system correctly
            context.translateBy(x: 50, y: pageRect.height - 50)
            
            // Create frame for text
            let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
            let textRect = CGRect(x: 0, y: -pageRect.height + 100,
                                width: pageRect.width - 100,
                                height: pageRect.height - 100)
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, attributedString.length), path, nil)
            
            CTFrameDraw(frame, context)
            context.endPage()
            context.closePDF()
            
            guard let pdfDocument = PDFDocument(data: pdfData as Data) else { return nil }
            return pdfDocument.page(at: 0)
        } catch {
            logger.error("Error creating PDF page: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func createPDFPage(from image: NSImage) -> PDFPage? {
        let imageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
        let pdfData = NSMutableData()
        
        var mediaBox = CGRect(origin: .zero, size: imageRect.size)
        guard let context = CGContext(consumer: CGDataConsumer(data: pdfData as CFMutableData)!,
                                    mediaBox: &mediaBox,
                                    nil) else { return nil }
        
        context.beginPDFPage(nil as CFDictionary?)
        
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
    
    func clearFiles() {
        files = []
        processedContent = ""
        processedPDF = nil
        error = nil
        progress = 0
        isProcessing = false
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
    
    func validateFile(_ url: URL) -> Bool {
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
    
    func moveFile(from source: Int, to destination: Int) {
        files.move(fromOffsets: IndexSet(integer: source), toOffset: destination)
        processFiles(mode: currentMode)
    }
    
    func removeFile(_ url: URL) {
        if let index = files.firstIndex(of: url) {
            files.remove(at: index)
            processFiles(mode: currentMode)
        }
    }
    
    func processDirectory(_ url: URL) -> [URL] {
        var files: [URL] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return files }
        
        for case let fileURL as URL in enumerator {
            autoreleasepool {
                do {
                    let resourceValues = try fileURL.resourceValues(forKeys: Set(keys))
                    if !resourceValues.isDirectory! {
                        let fileExtension = fileURL.pathExtension.lowercased()
                        if supportedTypes.contains(fileExtension) {
                            files.append(fileURL)
                        }
                    }
                } catch {
                    logger.error("Error processing directory: \(error.localizedDescription)")
                }
            }
        }
        
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    
    func buildFolderStructure(_ url: URL) throws -> FolderNode {
        var children: [FolderNode] = []
        
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .skipsHiddenFiles
        )
        
        for contentUrl in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let isDirectory = try contentUrl.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
            if isDirectory {
                children.append(try buildFolderStructure(contentUrl))
            } else if supportedTypes.contains(contentUrl.pathExtension.lowercased()) {
                children.append(FolderNode(url: contentUrl))
            }
        }
        
        return FolderNode(url: url, children: children)
    }
    
    private func processFile(_ url: URL, mode: ContentView.Mode) {
        guard validateFile(url) else { return }
        
        do {
            switch mode {
            case .prompt:
                try processFilesForPrompt([url])
            case .pdf:
                try processFilesForPDF([url])
            }
        } catch {
            DispatchQueue.main.async {
                self.error = error.localizedDescription
                self.isProcessing = false
            }
            logger.error("Error processing file: \(error.localizedDescription)")
        }
    }
    
    private func renderTreeStructure(_ node: FolderNode, indent: String = "") -> String {
        var result = "\(indent)- \(node.url.lastPathComponent)\n"
        for child in node.children {
            result += renderTreeStructure(child, indent: indent + "  ")
        }
        return result
    }
    
    private func processFile(_ url: URL) throws -> String {
        // Check if it's a special directory-based file type
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            let ext = url.pathExtension.lowercased()
            if ["xcodeproj", "xcworkspace", "project", "workspace"].contains(ext) {
                // Process project directory contents
                return try processProjectDirectory(url)
            }
        }
        
        // Handle regular files
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "lock", "package-lock.json", "yarn.lock", "gemfile.lock":
            return try processLockFile(url)
        case "xcodeproj", "xcworkspace", "project", "workspace":
            return try processProjectFile(url)
        default:
            return try String(contentsOf: url, encoding: .utf8)
        }
    }
    
    private func processProjectDirectory(_ url: URL) throws -> String {
        // Extract relevant metadata and files from project directories
        var content = "Project: \(url.lastPathComponent)\n\n"
        
        // Process common project files
        let commonFiles = ["project.pbxproj", "contents.xcworkspacedata", 
                          "Package.swift", "build.gradle"]
        
        for file in commonFiles {
            let fileURL = url.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                content += "File: \(file)\n"
                content += try String(contentsOf: fileURL, encoding: .utf8)
                content += "\n\n"
            }
        }
        
        return content
    }
    
    private func createPDFPage(from attributedString: NSAttributedString) -> PDFPage? {
        let pdfData = NSMutableData()
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter size
        var mediaBox = pageRect
        
        guard let context = CGContext(consumer: CGDataConsumer(data: pdfData as CFMutableData)!,
                                    mediaBox: &mediaBox,
                                    nil) else {
            return nil
        }
        
        context.beginPage(mediaBox: &mediaBox)
        
        // Create frame for text
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        let textRect = CGRect(x: 36, y: 36, width: pageRect.width - 72, height: pageRect.height - 72)
        let path = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        
        CTFrameDraw(frame, context)
        context.endPage()
        context.closePDF()
        
        guard let pdfDocument = PDFDocument(data: pdfData as Data) else { return nil }
        return pdfDocument.page(at: 0)
    }
    
    private func processLockFile(_ url: URL) throws -> String {
        // Read lock file content
        let content = try String(contentsOf: url, encoding: .utf8)
        
        // Add metadata header
        let header = """
        Lock File Analysis
        Path: \(url.path)
        Size: \(try FileManager.default.attributesOfItem(atPath: url.path)[.size] ?? 0) bytes
        Last Modified: \(try FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] ?? Date())
        
        Content:
        """
        
        return "\(header)\n\(content)"
    }
    
    private func processProjectFile(_ url: URL) throws -> String {
        // For project files, we want to extract relevant metadata
        var content = "Project File: \(url.lastPathComponent)\n\n"
        
        if url.pathExtension == "xcodeproj" {
            // Handle Xcode project files
            let pbxprojURL = url.appendingPathComponent("project.pbxproj")
            if FileManager.default.fileExists(atPath: pbxprojURL.path) {
                content += try String(contentsOf: pbxprojURL, encoding: .utf8)
            }
        } else {
            // For other project files, read directly
            content += try String(contentsOf: url, encoding: .utf8)
        }
        
        return content
    }
    
    private func processFileForPrompt(_ url: URL) throws -> String {
        // Get file extension
        let ext = url.pathExtension.lowercased()
        
        // Create header with file info
        var content = "File: \(url.lastPathComponent)\n"
        content += "Type: \(ext)\n"
        
        // Add file metadata
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attributes[.size] as? Int64 {
            content += "Size: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))\n"
        }
        if let modDate = attributes[.modificationDate] as? Date {
            content += "Modified: \(modDate)\n"
        }
        content += "\nContent:\n"
        
        // Process content based on file type
        switch ext {
        case "pdf":
            if let pdf = PDFDocument(url: url),
               let text = pdf.string {
                content += text
            } else {
                throw DocumentError.extractionFailed(reason: "Could not extract text from PDF")
            }
            
        case "doc", "docx", "pages", "odt":
            content += try DocumentProcessor.extractText(from: url)
            
        case "jpg", "jpeg", "png", "gif", "heic", "tiff", "webp":
            content += "[Image File]\n"
            if let image = NSImage(contentsOf: url) {
                content += "Dimensions: \(Int(image.size.width))×\(Int(image.size.height))"
            }
            
        default:
            // For text-based files, read directly
            content += try String(contentsOf: url, encoding: .utf8)
        }
        
        return content
    }
}

// Helper class to track processing state
private class ProcessingState {
    var isCompleted: Bool = false
    var error: Error?
} 

struct FolderNode: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var children: [FolderNode] = []
    
    static func == (lhs: FolderNode, rhs: FolderNode) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
} 
