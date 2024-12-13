import Foundation
import AppKit
import UniformTypeIdentifiers
import PDFKit
import os.log

private let logger = Logger(subsystem: "me.nuanc.Uno", category: "DocumentProcessor")

class DocumentProcessor {
    static func extractText(from url: URL) throws -> String {
        let type = url.pathExtension.lowercased()
        
        switch type {
        case "doc", "docx":
            // Try multiple approaches in order of preference
            
            // 1. Try Word format first (best for newer .docx)
            if let attrs = try? NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.docFormat],
                documentAttributes: nil
            ) {
                return attrs.string
            }
            
            // 2. Try RTF format (better for older .doc)
            if let attrs = try? NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ) {
                return attrs.string
            }
            
            // 3. Try plain text as last resort
            if let attrs = try? NSAttributedString(
                url: url,
                options: [
                    .documentType: NSAttributedString.DocumentType.plain,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
            ) {
                return attrs.string
            }
            
            // 4. If all else fails, try PDFKit
            if let pdf = PDFDocument(url: url),
               let text = pdf.string {
                return text
            }
            
            throw DocumentError.extractionFailed(reason: "Could not extract text from document: \(url.lastPathComponent)")
            
        case "pdf":
            if let pdf = PDFDocument(url: url),
               let text = pdf.string {
                return text
            }
            throw DocumentError.extractionFailed(reason: "Could not extract text from PDF: \(url.lastPathComponent)")
            
        default:
            return try String(contentsOf: url, encoding: .utf8)
        }
    }
    
    static func generateThumbnail(for url: URL, size: CGSize) async throws -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 1.0
        let scaledSize = CGSize(width: size.width * scale, height: size.height * scale)
        
        // Handle PDF files
        if url.pathExtension.lowercased() == "pdf",
           let pdfDoc = PDFDocument(url: url),
           let pdfPage = pdfDoc.page(at: 0) {
            let thumbnail = NSImage(size: scaledSize)
            
            thumbnail.lockFocus()
            if let ctx = NSGraphicsContext.current {
                ctx.imageInterpolation = .high
                let drawRect = CGRect(origin: .zero, size: scaledSize)
                pdfPage.draw(with: .mediaBox, to: drawRect as! CGContext)
            }
            thumbnail.unlockFocus()
            
            return thumbnail
        }
        
        // Handle non-PDF files
        if let image = NSImage(contentsOf: url) {
            let thumbnail = NSImage(size: scaledSize)
            thumbnail.lockFocus()
            
            // Calculate aspect ratio preserving dimensions
            let imageSize = image.size
            let scale = min(scaledSize.width / imageSize.width,
                           scaledSize.height / imageSize.height)
            let scaledWidth = imageSize.width * scale
            let scaledHeight = imageSize.height * scale
            let x = (scaledSize.width - scaledWidth) / 2
            let y = (scaledSize.height - scaledHeight) / 2
            
            image.draw(in: CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight),
                      from: CGRect(origin: .zero, size: image.size),
                      operation: .copy,
                      fraction: 1.0)
            
            thumbnail.unlockFocus()
            return thumbnail
        }
        
        throw DocumentError.extractionFailed(reason: "Could not generate thumbnail for: \(url.lastPathComponent)")
    }
    
    static func createPDF(from urls: [URL]) throws -> PDFDocument {
        let pdfDocument = PDFDocument()
        var currentPage = 0
        
        for url in urls {
            switch url.pathExtension.lowercased() {
            case "pdf":
                if let pdf = PDFDocument(url: url) {
                    for i in 0..<pdf.pageCount {
                        if let page = pdf.page(at: i) {
                            pdfDocument.insert(page, at: currentPage)
                            currentPage += 1
                        }
                    }
                }
                
            case "png", "jpg", "jpeg", "gif":
                if let image = NSImage(contentsOf: url),
                   let page = createPDFPage(from: image) {
                    pdfDocument.insert(page, at: currentPage)
                    currentPage += 1
                }
                
            default:
                if let textContent = try? String(contentsOf: url, encoding: .utf8),
                   let page = createPDFPage(from: textContent) {
                    pdfDocument.insert(page, at: currentPage)
                    currentPage += 1
                }
            }
        }
        
        return pdfDocument
    }
    
    private static func createPDFPage(from image: NSImage) -> PDFPage? {
        let pdfData = NSMutableData()
        let imageRect = CGRect(origin: .zero, size: image.size)
        var mediaBox = imageRect
        
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(consumer: CGDataConsumer(data: pdfData as CFMutableData)!,
                                    mediaBox: &mediaBox,
                                    nil) else {
            return nil
        }
        
        context.beginPage(mediaBox: &mediaBox)
        context.draw(cgImage, in: imageRect)
        context.endPage()
        context.closePDF()
        
        guard let pdfDocument = PDFDocument(data: pdfData as Data) else { return nil }
        return pdfDocument.page(at: 0)
    }
    
    private static func createPDFPage(from text: String) -> PDFPage? {
        let pdfData = NSMutableData()
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter size
        var mediaBox = pageRect
        
        guard let context = CGContext(consumer: CGDataConsumer(data: pdfData as CFMutableData)!,
                                    mediaBox: &mediaBox,
                                    nil) else {
            return nil
        }
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.textColor
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attrs)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        
        context.beginPage(mediaBox: &mediaBox)
        let textRect = CGRect(x: 36, y: 36, width: pageRect.width - 72, height: pageRect.height - 72)
        let path = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        
        CTFrameDraw(frame, context)
        context.endPage()
        context.closePDF()
        
        guard let pdfDocument = PDFDocument(data: pdfData as Data) else { return nil }
        return pdfDocument.page(at: 0)
    }
}

enum DocumentError: Error {
    case extractionFailed(reason: String)
} 
