import Foundation
import PDFKit
import AppKit
import os.log
import CoreGraphics

private let logger = Logger(subsystem: "me.nuanc.Uno", category: "PDFProcessor")

// PDF metadata constants
private let kCGPDFContextAuthor = "Author" as CFString
private let kCGPDFContextTitle = "Title" as CFString
private let kCGPDFContextCreationDate = "CreationDate" as CFString

enum PDFProcessorError: Error {
    case invalidPDF
    case imageProcessingFailed
    case textProcessingFailed
}

struct Progress {
    let currentFile: String
    let fileProgress: Double
    var totalProgress: Double
    
    init(currentFile: String, fileProgress: Double, totalProgress: Double) {
        self.currentFile = currentFile
        self.fileProgress = fileProgress
        self.totalProgress = totalProgress
    }
}

class PDFProcessor {
    private var outline: [PDFOutline] = []
    
    func createPDF(from urls: [URL], progressHandler: @escaping (Progress) -> Void) throws -> PDFDocument {
        let pdfDocument = PDFDocument()
        let totalFiles = Double(urls.count)
        
        for (index, url) in urls.enumerated() {
            try autoreleasepool {
                do {
                    let currentProgress = Progress(
                        currentFile: url.lastPathComponent,
                        fileProgress: 0.0,
                        totalProgress: Double(index) / totalFiles
                    )
                    progressHandler(currentProgress)
                    
                    switch url.pathExtension.lowercased() {
                    case "pdf":
                        try processExistingPDF(url, into: pdfDocument)
                    case "png", "jpg", "jpeg", "heic", "tiff":
                        try processImageFile(url, into: pdfDocument)
                    default:
                        try processTextFile(url, into: pdfDocument)
                    }
                    
                    // Update progress after processing
                    let updatedProgress = Progress(
                        currentFile: url.lastPathComponent,
                        fileProgress: 1.0,
                        totalProgress: Double(index + 1) / totalFiles
                    )
                    progressHandler(updatedProgress)
                    
                } catch {
                    logger.error("Error processing file: \(error.localizedDescription)")
                    throw error
                }
            }
        }
        
        return pdfDocument
    }
    
    private func processExistingPDF(_ url: URL, into document: PDFDocument) throws {
        guard let sourcePDF = PDFDocument(url: url) else {
            throw PDFProcessorError.invalidPDF
        }
        
        for i in 0..<sourcePDF.pageCount {
            if let page = sourcePDF.page(at: i) {
                document.insert(page, at: document.pageCount)
            }
        }
    }
    
    private func processImageFile(_ url: URL, into document: PDFDocument) throws {
        guard let image = NSImage(contentsOf: url) else {
            throw PDFProcessorError.imageProcessingFailed
        }
        
        if let page = createPDFPage(from: image) {
            document.insert(page, at: document.pageCount)
        } else {
            throw PDFProcessorError.imageProcessingFailed
        }
    }
    
    private func processTextFile(_ url: URL, into document: PDFDocument) throws {
        // Implementation for text file processing
        // This would need to be implemented based on your requirements
    }
    
    private func createPDFPage(from image: NSImage) -> PDFPage? {
        // Implementation for creating PDF page from image
        // This would need to be implemented based on your requirements
        return nil
    }
}

// Extension for outline handling
extension PDFProcessor {
    private func addOutline(to document: PDFDocument, outline: [PDFOutline]) {
        guard !outline.isEmpty else { return }
        
        let root = PDFOutline()
        root.label = "Document Outline"
        document.outlineRoot = root
        
        for item in outline {
            root.insertChild(item, at: root.numberOfChildren)
        }
    }
} 