import SwiftUI
import PDFKit

struct PDFKitView: NSViewRepresentable {
    var document: PDFDocument
    var zoomLevel: CGFloat
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .clear
        pdfView.pageBreakMargins = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        
        // Set up main view configurations
        pdfView.delegate = context.coordinator
        pdfView.displayBox = .cropBox
        pdfView.enableDataDetectors = false
        
        return pdfView
    }
    
    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document != document {
            pdfView.document = document
            pdfView.autoScales = true // Reset this for new document
            pdfView.goToFirstPage(nil)
        }
        
        pdfView.scaleFactor = zoomLevel
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PDFViewDelegate {
        var parent: PDFKitView
        
        init(_ parent: PDFKitView) {
            self.parent = parent
        }
        
        // Fix: Correctly implement PDFViewDelegate protocol
        func pdfView(_ sender: PDFView, willClickOnLink link: PDFAnnotation) -> Bool {
            // Handle link clicks
            return false // Return true to allow default behavior
        }
    }
} 