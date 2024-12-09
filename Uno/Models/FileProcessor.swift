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
    
    let supportedTypes = [
        "swift", "ts", "js", "html", "css", "txt", "md", "json", 
        "pdf", "py", "java", "cpp", "c", "h", "m", "mm", "rb", "php"
    ]
    
    private let maxFileSize: Int64 = 100 * 1024 * 1024 // 100MB limit
    
    func processFiles(mode: ContentView.Mode) {
        logger.debug("Starting file processing with mode: \(String(describing: mode))")
        isProcessing = true
        error = nil
        progress = 0
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                logger.error("Self was deallocated during processing")
                return
            }
            
            // Validate files before processing
            for url in self.files {
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                    let fileSize = attributes[.size] as? Int64 ?? 0
                    logger.debug("Validating file: \(url.lastPathComponent), size: \(fileSize)")
                    
                    if fileSize > self.maxFileSize {
                        logger.error("File too large: \(url.lastPathComponent)")
                        DispatchQueue.main.async {
                            self.error = "File too large: \(url.lastPathComponent)"
                            self.isProcessing = false
                        }
                        return
                    }
                } catch {
                    logger.error("Error accessing file: \(url.lastPathComponent), error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.error = "Error accessing file: \(url.lastPathComponent)"
                        self.isProcessing = false
                    }
                    return
                }
            }
            
            logger.debug("File validation complete, processing \(self.files.count) files")
            
            switch mode {
            case .prompt:
                self.processFilesForPrompt()
            case .pdf:
                self.processFilesForPDF()
            }
        }
    }
    
    private func processFilesForPrompt() {
        var result = ""
        let totalFiles = Double(files.count)
        
        for (index, url) in files.enumerated() {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let filename = url.lastPathComponent
                result += "<\(filename)>\n\(content)\n</\(filename)>\n\n"
                
                DispatchQueue.main.async {
                    self.progress = Double(index + 1) / totalFiles
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = "Error reading file: \(url.lastPathComponent)"
                }
                continue
            }
        }
        
        DispatchQueue.main.async {
            self.processedContent = result
            self.progress = 1.0
            self.isProcessing = false
        }
    }
    
    private func processFilesForPDF() {
        let pdfDocument = PDFDocument()
        let totalFiles = Double(files.count)
        
        for (index, url) in files.enumerated() {
            autoreleasepool {
                if url.pathExtension.lowercased() == "pdf" {
                    if let existingPDF = PDFDocument(url: url) {
                        for i in 0..<existingPDF.pageCount {
                            if let page = existingPDF.page(at: i) {
                                pdfDocument.insert(page, at: pdfDocument.pageCount)
                            }
                        }
                    }
                } else {
                    if let pdfPage = createPDFPage(from: url) {
                        pdfDocument.insert(pdfPage, at: pdfDocument.pageCount)
                    }
                }
                
                DispatchQueue.main.async {
                    self.progress = Double(index + 1) / totalFiles
                }
            }
        }
        
        DispatchQueue.main.async {
            self.processedPDF = pdfDocument
            self.progress = 1.0
            self.isProcessing = false
        }
    }
    
    private func createPDFPage(from url: URL) -> PDFPage? {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            
            // Create an attributed string with monospace font
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.textColor
            ]
            
            let attributedString = NSAttributedString(string: content, attributes: attributes)
            
            // Create the PDF page with proper settings
            let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter size
            let pdfData = NSMutableData()
            
            // Create PDF context with proper media box
            var mediaBox = CGRect(origin: .zero, size: pageRect.size)
            guard let context = CGContext(consumer: CGDataConsumer(data: pdfData as CFMutableData)!,
                                        mediaBox: &mediaBox,
                                        [kCGPDFContextMediaBox as String: mediaBox] as CFDictionary) else {
                return nil
            }
            
            // Begin PDF page with proper settings
            let pageInfo = [
                kCGPDFContextMediaBox as String: mediaBox
            ] as CFDictionary
            
            context.beginPDFPage(pageInfo)
            
            // Create PDF context and draw text
            let frameSetter = CTFramesetterCreateWithAttributedString(attributedString)
            let path = CGPath(rect: CGRect(x: 36, y: 36, width: 540, height: 720), transform: nil)
            let frame = CTFramesetterCreateFrame(frameSetter, CFRangeMake(0, 0), path, nil)
            
            context.translateBy(x: 0, y: pageRect.height)
            context.scaleBy(x: 1.0, y: -1.0)
            
            CTFrameDraw(frame, context)
            
            context.endPDFPage()
            context.closePDF()
            
            // Create PDF document from data
            guard let pdfDocument = PDFDocument(data: pdfData as Data),
                  let page = pdfDocument.page(at: 0) else {
                return nil
            }
            
            return page
        } catch {
            print("Error creating PDF page: \(error)")
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
        currentMode = mode
        if !files.isEmpty {
            processFiles(mode: mode)
        }
    }
} 
