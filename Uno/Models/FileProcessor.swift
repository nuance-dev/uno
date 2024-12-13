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
    @Published private(set) var lastProcessedFiles: [URL] = []

    private let processingQueue = DispatchQueue(label: "me.nuanc.Uno.processing", qos: .userInitiated, attributes: .concurrent)
    private let progressQueue = DispatchQueue(label: "me.nuanc.Uno.progress")
    private let maxConcurrentOperations = 4
    
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
    
    private let memoryManager = MemoryManager.shared
    private let performanceMonitor = PerformanceMonitor.shared
    
    func processFiles(mode: ContentView.Mode) {
        // Explicitly type the operation closure
        let operation: () -> Void = { [weak self] in
            guard let self = self else { return }
            
            // Set initial state on main thread
            DispatchQueue.main.async {
                self.currentMode = mode
                self.isProcessing = true
                self.error = nil
                self.progress = 0
            }
            
            // Process files
            let sortedFiles = self.files.sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            switch mode {
            case .prompt:
                self.processFilesForPrompt(sortedFiles)
            case .pdf:
                self.processFilesForPDF(sortedFiles)
            }
        }
        
        // Execute the operation with explicit typing
        performanceMonitor.trackOperation("processFiles", operation: operation)
    }
    
    private func processFilesForPrompt(_ files: [URL]) {
        let totalFiles = Double(files.count)
        
        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = maxConcurrentOperations
        
        var results: [(index: Int, content: String)] = []
        let resultsQueue = DispatchQueue(label: "me.nuanc.Uno.results")
        let group = DispatchGroup()
        
        for (index, url) in files.enumerated() {
            group.enter()
            
            operationQueue.addOperation {
                autoreleasepool {
                    do {
                        let content: String
                        
                        switch url.pathExtension.lowercased() {
                        case "doc", "docx":
                            content = try DocumentProcessor.extractText(from: url)
                        case "pdf":
                            if let pdf = PDFDocument(url: url),
                               let text = pdf.string {
                                content = text
                            } else {
                                throw NSError(domain: "PDFError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not extract text from PDF"])
                            }
                        default:
                            content = try String(contentsOf: url, encoding: .utf8)
                        }
                        
                        // Wrap content with filename tags
                        let wrappedContent = "<\(url.lastPathComponent)>\n\(content)\n</\(url.lastPathComponent)>"
                        
                        resultsQueue.async {
                            results.append((index, wrappedContent))
                        }
                        
                        DispatchQueue.main.async {
                            self.progress = Double(index + 1) / totalFiles
                        }
                        
                    } catch {
                        logger.error("Error processing file: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            self.error = "Error processing \(url.lastPathComponent): \(error.localizedDescription)"
                        }
                    }
                }
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            let sortedResults = results.sorted { $0.index < $1.index }
            let finalContent = sortedResults.map { $0.content }.joined(separator: "\n\n")
            
            self.processedContent = finalContent
            self.progress = 1.0
            self.isProcessing = false
        }
    }
    
    private func processFilesForPDF(_ files: [URL]) {
        let pdfDocument = PDFDocument()
        let chunks = files.chunked(into: memoryManager.recommendedChunkSize)
        
        for (index, chunk) in chunks.enumerated() {
            autoreleasepool {
                processChunk(chunk, into: pdfDocument)
                DispatchQueue.main.async {
                    self.progress = Double(index + 1) / Double(chunks.count)
                }
                memoryManager.cleanupIfNeeded()
            }
        }
        
        DispatchQueue.main.async {
            self.processedPDF = pdfDocument
            self.isProcessing = false
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
                .foregroundColor: NSColor.black,
                .paragraphStyle: style,
                .backgroundColor: NSColor.clear
            ]
            
            let attributedString = NSAttributedString(string: content, attributes: attributes)
            
            // Create PDF page
            let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
            let pdfData = NSMutableData()
            
            var mediaBox = CGRect(origin: .zero, size: pageRect.size)
            guard let context = CGContext(consumer: CGDataConsumer(data: pdfData as CFMutableData)!,
                                        mediaBox: &mediaBox,
                                        nil) else { return nil }
            
            context.beginPDFPage(nil as CFDictionary?)
            
            // Draw the text
            let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
            let textRect = pageRect.insetBy(dx: 50, dy: 50) // Add margins
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, attributedString.length), path, nil)
            
            context.translateBy(x: 0, y: pageRect.height)
            context.scaleBy(x: 1.0, y: -1.0)
            CTFrameDraw(frame, context)
            
            context.endPDFPage()
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
}

// Helper class to track processing state
private class ProcessingState {
    var isCompleted: Bool = false
    var error: Error?
} 
