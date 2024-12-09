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
                    if url.pathExtension.lowercased() == "pdf" {
                        if let pdf = PDFDocument(url: url),
                           let text = pdf.string {
                            result += "<\(url.lastPathComponent)>\n\(text)\n</\(url.lastPathComponent)>\n\n"
                        }
                    } else {
                        let content = try String(contentsOf: url, encoding: .utf8)
                        result += "<\(url.lastPathComponent)>\n\(content)\n</\(url.lastPathComponent)>\n\n"
                    }
                    
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
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.textColor
            ]
            
            let attributedString = NSAttributedString(string: content, attributes: attributes)
            let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
            let pdfData = NSMutableData()
            
            guard let context = CGContext(consumer: CGDataConsumer(data: pdfData as CFMutableData)!,
                                        mediaBox: nil,
                                        nil) else { return nil }
            
            context.beginPDFPage(nil)
            
            let frameSetter = CTFramesetterCreateWithAttributedString(attributedString)
            let path = CGPath(rect: CGRect(x: 36, y: 36, width: 540, height: 720), transform: nil)
            let frame = CTFramesetterCreateFrame(frameSetter, CFRangeMake(0, 0), path, nil)
            
            context.translateBy(x: 0, y: pageRect.height)
            context.scaleBy(x: 1.0, y: -1.0)
            
            CTFrameDraw(frame, context)
            
            context.endPDFPage()
            context.closePDF()
            
            guard let pdfDocument = PDFDocument(data: pdfData as Data),
                  let page = pdfDocument.page(at: 0) else { return nil }
            
            return page
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
