import SwiftUI
import PDFKit
import UniformTypeIdentifiers

class FileProcessor: ObservableObject {
    @Published var files: [URL] = []
    @Published var isProcessing = false
    @Published var processedContent: String = ""
    @Published var processedPDF: PDFDocument?
    @Published var error: String?
    
    private let supportedTypes = [
        "swift", "ts", "js", "html", "css", "txt", "md", "json", 
        "pdf", "py", "java", "cpp", "c", "h", "m", "mm", "rb", "php"
    ]
    
    func processFiles(mode: ContentView.Mode) {
        isProcessing = true
        error = nil
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
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
        
        for url in files {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                let filename = url.lastPathComponent
                result += "<\(filename)>\n\(content)\n</\(filename)>\n\n"
            } catch {
                DispatchQueue.main.async {
                    self.error = "Error reading file: \(url.lastPathComponent)"
                }
                continue
            }
        }
        
        DispatchQueue.main.async {
            self.processedContent = result
            self.isProcessing = false
        }
    }
    
    private func processFilesForPDF() {
        let pdfDocument = PDFDocument()
        
        for (index, url) in files.enumerated() {
            if url.pathExtension.lowercased() == "pdf" {
                if let existingPDF = PDFDocument(url: url) {
                    for i in 0..<existingPDF.pageCount {
                        if let page = existingPDF.page(at: i) {
                            pdfDocument.insert(page, at: pdfDocument.pageCount)
                        }
                    }
                }
            } else {
                // Convert non-PDF files to PDF
                if let pdfPage = createPDFPage(from: url) {
                    pdfDocument.insert(pdfPage, at: pdfDocument.pageCount)
                }
            }
        }
        
        DispatchQueue.main.async {
            self.processedPDF = pdfDocument
            self.isProcessing = false
        }
    }
    
    private func createPDFPage(from url: URL) -> PDFPage? {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let data = content.data(using: .utf8)!
            
            // Create an attributed string with monospace font
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            ]
            let attributedString = NSAttributedString(string: content, attributes: attrs)
            
            // Create PDF page
            let pageRect = NSRect(x: 0, y: 0, width: 612, height: 792) // US Letter size
            let pdfData = NSMutableData()
            let consumer = CGDataConsumer(data: pdfData as CFMutableData)!
            
            var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
            let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)!
            
            let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
            let framePath = CGPath(rect: CGRect(x: 36, y: 36, width: 540, height: 720), transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), framePath, nil)
            
            context.beginPage(mediaBox: &mediaBox)
            CTFrameDraw(frame, context)
            context.endPage()
            context.closePDF()
            
            if let pdfDocument = PDFDocument(data: pdfData as Data) {
                return pdfDocument.page(at: 0)
            }
        } catch {
            DispatchQueue.main.async {
                self.error = "Error converting file: \(url.lastPathComponent)"
            }
        }
        return nil
    }
    
    func clearFiles() {
        files = []
        processedContent = ""
        processedPDF = nil
        error = nil
    }
} 