import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import os
import CoreServices
import QuickLook
import QuickLookThumbnailing

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
    
    let supportedTypes = [
        // Code files
        "swift", "ts", "js", "html", "css", "jsx", "tsx", "vue", "php",
        "py", "rb", "java", "cpp", "c", "h", "cs", "go", "rs", "kt",
        "scala", "m", "mm", "pl", "sh", "bash", "zsh", "sql", "r",
        // Data files
        "json", "yaml", "yml", "xml", "csv", "toml",
        // Documentation
        "md", "mdx", "txt", "rtf", "tex", "doc", "docx", "rst", "adoc", "org",
        "wiki", "textile", "pod", "markdown", "mdown", "mkdn", "mkd",
        // Config files
        "ini", "conf", "config", "env", "gitignore", "dockerignore",
        "eslintrc", "prettierrc", "babelrc", "editorconfig",
        // Web files
        "scss", "sass", "less", "svg", "graphql", "wasm", "astro", "svelte",
        "postcss", "prisma", "proto", "hbs", "ejs", "pug",
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
    
    func processFiles(mode: ContentView.Mode) {
        currentMode = mode
        logger.debug("Starting file processing in mode")
        isProcessing = true
        error = nil
        progress = 0
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let sortedFiles = self.files.sorted { $0.lastPathComponent < $1.lastPathComponent }
            
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
    
    private func processFilesForPrompt(_ files: [URL]) {
        var result = ""
        let totalFiles = Double(files.count)
        
        for (index, url) in files.enumerated() {
            autoreleasepool {
                do {
                    DispatchQueue.main.async {
                        self.progress = Double(index) / totalFiles
                    }
                    
                    let content: String
                    
                    switch url.pathExtension.lowercased() {
                    case "pdf":
                        if let pdf = PDFDocument(url: url),
                           let text = pdf.string {
                            content = text
                        } else {
                            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not extract PDF text"])
                        }
                        
                    case "doc", "docx":
                        // Use textutil directly for Office documents
                        let process = Process()
                        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
                        process.arguments = ["-convert", "txt", "-stdout", url.path]
                        
                        let pipe = Pipe()
                        process.standardOutput = pipe
                        
                        try process.run()
                        process.waitUntilExit()
                        
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        if let text = String(data: data, encoding: .utf8) {
                            content = text
                        } else {
                            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not convert document to text"])
                        }
                        
                    default:
                        content = try String(contentsOf: url, encoding: .utf8)
                    }
                    
                    result += "<\(url.lastPathComponent)>\n\(content)\n</\(url.lastPathComponent)>\n\n"
                    
                    DispatchQueue.main.async {
                        self.progress = Double(index + 1) / totalFiles
                    }
                } catch {
                    logger.error("Error processing file \(url.lastPathComponent): \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.error = "Error processing \(url.lastPathComponent): \(error.localizedDescription)"
                    }
                }
            }
        }
        
        DispatchQueue.main.async {
            self.processedContent = result
            self.progress = 1.0
            self.isProcessing = false
        }
    }
    
    private func processFilesForPDF(_ files: [URL]) {
        let pdfDocument = PDFDocument()
        let totalFiles = Double(files.count)
        
        for (index, url) in files.enumerated() {
            autoreleasepool {
                do {
                    switch url.pathExtension.lowercased() {
                    case "pdf":
                        if let existingPDF = PDFDocument(url: url) {
                            for i in 0..<existingPDF.pageCount {
                                if let page = existingPDF.page(at: i) {
                                    pdfDocument.insert(page, at: pdfDocument.pageCount)
                                }
                            }
                        }
                        
                    case "doc", "docx":
                        // Use the more robust conversion method
                        if let convertedPDF = convertDocumentToPDF(url) {
                            for i in 0..<convertedPDF.pageCount {
                                if let page = convertedPDF.page(at: i) {
                                    pdfDocument.insert(page, at: pdfDocument.pageCount)
                                }
                            }
                        } else {
                            throw NSError(domain: "", code: -1, 
                                        userInfo: [NSLocalizedDescriptionKey: "Could not convert document to PDF"])
                        }
                        
                    default:
                        if let pages = createPDFPage(from: url) {
                            for page in pages {
                                pdfDocument.insert(page, at: pdfDocument.pageCount)
                            }
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self.progress = Double(index + 1) / totalFiles
                    }
                } catch {
                    logger.error("Error processing file for PDF: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.error = "Error processing \(url.lastPathComponent): \(error.localizedDescription)"
                    }
                }
            }
        }
        
        DispatchQueue.main.async {
            self.processedPDF = pdfDocument
            self.progress = 1.0
            self.isProcessing = false
        }
    }
    
    private func createPDFPage(from url: URL) -> [PDFPage]? {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            
            // Create attributed string with improved formatting
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 2
            style.paragraphSpacing = 10
            style.alignment = .left
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.black,
                .paragraphStyle: style
            ]
            
            let attributedString = NSAttributedString(string: content, attributes: attributes)
            var pages: [PDFPage] = []
            
            // Create PDF context
            let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter
            let pdfData = NSMutableData()
            
            guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return nil }
            var mediaBox = CGRect(origin: .zero, size: pageRect.size)
            
            guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
                return nil
            }
            
            // Create framesetter
            let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
            var currentRange = CFRangeMake(0, 0)
            var currentPage = 0
            
            // Get total pages needed
            let contentRect = CGRect(x: 50, y: 50, width: pageRect.width - 100, height: pageRect.height - 100)
            let path = CGPath(rect: contentRect, transform: nil)
            var done = false
            
            while !done {
                // Start new page
                context.beginPage(mediaBox: &mediaBox)
                
                // Fill white background
                context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
                context.fill(mediaBox)
                
                // Draw header
                let headerAttributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: NSColor.darkGray
                ]
                
                let headerText = "\(url.lastPathComponent) - Page \(currentPage + 1)"
                let headerString = NSAttributedString(string: headerText, attributes: headerAttributes)
                let headerRect = CGRect(x: 50, y: pageRect.height - 40, width: pageRect.width - 100, height: 20)
                
                context.saveGState()
                context.textMatrix = .identity
                headerString.draw(in: headerRect)
                context.restoreGState()
                
                // Create frame for this page
                let frame = CTFramesetterCreateFrame(framesetter, currentRange, path, nil)
                let frameRange = CTFrameGetVisibleStringRange(frame)
                
                // Draw the text
                context.saveGState()
                context.translateBy(x: 0, y: pageRect.height)
                context.scaleBy(x: 1.0, y: -1.0)
                CTFrameDraw(frame, context)
                context.restoreGState()
                
                context.endPage()
                
                // Check if we're done
                if frameRange.location + frameRange.length >= attributedString.length {
                    done = true
                } else {
                    // Move to next portion of text
                    currentRange = CFRangeMake(frameRange.location + frameRange.length, 0)
                    currentPage += 1
                }
            }
            
            context.closePDF()
            
            // Create PDF document and extract pages
            if let pdfDocument = PDFDocument(data: pdfData as Data) {
                for i in 0..<pdfDocument.pageCount {
                    if let page = pdfDocument.page(at: i) {
                        pages.append(page)
                    }
                }
                return pages
            }
            
            return nil
        } catch {
            logger.error("Error creating PDF pages: \(error.localizedDescription)")
            return nil
        }
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
    
    private func convertDocumentToPDF(_ url: URL) -> PDFDocument? {
        logger.debug("Converting document to PDF: \(url.lastPathComponent)")
        
        // Create temporary directory for conversion
        let tempDir = FileManager.default.temporaryDirectory
        let tempPDFURL = tempDir.appendingPathComponent(UUID().uuidString + ".pdf")
        
        do {
            // Try NSWorkspace first for Office documents
            if url.pathExtension.lowercased() == "docx" || url.pathExtension.lowercased() == "doc" {
                logger.debug("Using NSWorkspace for Office document conversion")
                
                let workspace = NSWorkspace.shared
                let configuration = [NSWorkspace.LaunchConfigurationKey.arguments: ["-convert-to", "pdf", url.path]]
                
                if let libreOfficePath = findLibreOffice() {
                    try workspace.launchApplication(at: URL(fileURLWithPath: libreOfficePath),
                                                 options: .default,
                                                 configuration: configuration)
                    
                    // Wait for conversion (max 30 seconds)
                    let outputURL = url.deletingPathExtension().appendingPathExtension("pdf")
                    var timeout = 30
                    while !FileManager.default.fileExists(atPath: outputURL.path) && timeout > 0 {
                        Thread.sleep(forTimeInterval: 1)
                        timeout -= 1
                    }
                    
                    if let pdf = PDFDocument(url: outputURL) {
                        try? FileManager.default.removeItem(at: outputURL)
                        return pdf
                    }
                }
            }
            
            // Fallback to QuickLook conversion
            logger.debug("Falling back to QuickLook conversion")
            let generator = QLThumbnailGenerator.shared
            let request = QLThumbnailGenerator.Request(
                fileAt: url,
                size: CGSize(width: 612, height: 792),
                scale: 2.0,
                representationTypes: [.thumbnail, .lowQualityThumbnail]
            )
            
            let semaphore = DispatchSemaphore(value: 0)
            var conversionError: Error?
            var pdfDocument: PDFDocument?
            
            generator.generateBestRepresentation(for: request) { (thumbnail, error) in
                defer { semaphore.signal() }
                
                if let error = error {
                    conversionError = error
                    logger.error("QuickLook conversion failed: \(error.localizedDescription)")
                    return
                }
                
                if let cgImage = thumbnail?.cgImage {
                    let pdfData = NSMutableData()
                    
                    if let consumer = CGDataConsumer(data: pdfData as CFMutableData) {
                        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
                        
                        if let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) {
                            context.beginPage(mediaBox: &mediaBox)
                            context.draw(cgImage, in: mediaBox)
                            context.endPage()
                            context.closePDF()
                            
                            pdfDocument = PDFDocument(data: pdfData as Data)
                        }
                    }
                }
            }
            
            _ = semaphore.wait(timeout: .now() + 30.0)
            
            if let error = conversionError {
                throw error
            }
            
            return pdfDocument
            
        } catch {
            logger.error("Document conversion failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func findLibreOffice() -> String? {
        let possiblePaths = [
            "/Applications/LibreOffice.app/Contents/MacOS/soffice",
            "/opt/homebrew/bin/soffice",
            "/usr/local/bin/soffice"
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        return nil
    }
    
    private func extractTextFromOfficeDocument(_ url: URL) throws -> String {
        logger.debug("Extracting text from Office document: \(url.lastPathComponent)")
        
        if let pdf = convertDocumentToPDF(url),
           let text = pdf.string {
            return text
        }
        
        // If PDF conversion fails, try direct text extraction
        if let data = try? Data(contentsOf: url) {
            // Try to extract text directly from DOCX
            if url.pathExtension.lowercased() == "docx" {
                let tempDir = FileManager.default.temporaryDirectory
                let tempURL = tempDir.appendingPathComponent(UUID().uuidString + ".docx")
                try data.write(to: tempURL)
                
                // Use textutil command line tool
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
                process.arguments = ["-convert", "txt", "-stdout", tempURL.path]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                try process.run()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                try? FileManager.default.removeItem(at: tempURL)
                
                if let text = String(data: data, encoding: .utf8) {
                    return text
                }
            }
        }
        
        throw NSError(domain: "", code: -1, 
                     userInfo: [NSLocalizedDescriptionKey: "Could not extract text from document"])
    }
} 
