import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import os

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
        "md", "txt", "rtf", "tex", "doc", "docx",
        // Config files
        "ini", "conf", "config", "env", "gitignore", "dockerignore",
        // Web files
        "scss", "sass", "less", "svg", "graphql", "wasm",
        // Images (for PDF mode)
        "pdf", "jpg", "jpeg", "png", "gif", "heic", "tiff", "webp"
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
                    // Update progress more frequently
                    DispatchQueue.main.async {
                        self.progress = Double(index) / totalFiles
                    }
                    
                    if url.pathExtension.lowercased() == "pdf" {
                        if let pdf = PDFDocument(url: url),
                           let text = pdf.string {
                            result += "<\(url.lastPathComponent)>\n\(text)\n</\(url.lastPathComponent)>\n\n"
                        }
                    } else {
                        let content = try String(contentsOf: url, encoding: .utf8)
                        result += "<\(url.lastPathComponent)>\n\(content)\n</\(url.lastPathComponent)>\n\n"
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
                    let _: PDFPage?
                    
                    switch url.pathExtension.lowercased() {
                    case "pdf":
                        if let existingPDF = PDFDocument(url: url) {
                            for i in 0..<existingPDF.pageCount {
                                if let page = existingPDF.page(at: i) {
                                    pdfDocument.insert(page, at: pdfDocument.pageCount)
                                }
                            }
                        }
                        
                    case "jpg", "jpeg", "png", "gif", "heic", "tiff":
                        if let image = NSImage(contentsOf: url),
                           let page = createPDFPage(from: image) {
                            pdfDocument.insert(page, at: pdfDocument.pageCount)
                        }
                        
                    default:
                        if let textPage = createPDFPage(from: url) {
                            pdfDocument.insert(textPage, at: pdfDocument.pageCount)
                        }
                    }
                    
                    DispatchQueue.main.async {
                        self.progress = Double(index + 1) / totalFiles
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
    
    private func createPDFPage(from url: URL) -> PDFPage? {
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
            
            guard let consumer = CGDataConsumer(data: pdfData as CFMutableData) else { return nil }
            
            // Create PDF context with white background
            var mediaBox = CGRect(origin: .zero, size: pageRect.size)
            
            guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
                return nil
            }
            
            // Start PDF page
            context.beginPage(mediaBox: &mediaBox)
            
            // Fill white background explicitly
            context.setFillColor(CGColor(gray: 1.0, alpha: 1.0))
            context.fill(mediaBox)
            
            // Add header with file info
            let headerAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.darkGray
            ]
            
            let headerText = "\(url.lastPathComponent)"
            let headerString = NSAttributedString(string: headerText, attributes: headerAttributes)
            
            // Draw header
            let headerRect = CGRect(x: 50, y: pageRect.height - 40, width: pageRect.width - 100, height: 20)
            
            // Create content frame
            let contentRect = CGRect(x: 50, y: 50, width: pageRect.width - 100, height: pageRect.height - 100)
            let path = CGPath(rect: contentRect, transform: nil)
            
            // Draw content
            let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
            
            // Draw header (in correct orientation)
            context.saveGState()
            context.textMatrix = .identity
            headerString.draw(in: headerRect)
            context.restoreGState()
            
            // Draw main content
            context.saveGState()
            CTFrameDraw(frame, context)
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
} 
