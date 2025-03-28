import SwiftUI
import PDFKit
import os // For logger

struct EnhancedPDFKitView: NSViewRepresentable {
    let pdfDocument: PDFDocument
    @Binding var zoomLevel: CGFloat // Use binding if external control needed
    
    // Add logger for debugging
    private static let logger = Logger(subsystem: "me.nuanc.Uno", category: "PDFView")

    // Add Coordinator for delegate methods if needed (e.g., page change notifications)

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        configurePDFView(pdfView) // Centralize config
        // Set Coordinator as delegate if implementing delegate methods
        // pdfView.delegate = context.coordinator
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        var needsLayoutUpdate = false
        // Self.logger.debug("EnhancedPDFKitView updateNSView called") // Debug print

        if pdfView.document != pdfDocument {
            // Self.logger.debug("PDF Document changed, updating PDFView") // Debug print
            pdfView.document = pdfDocument
            // Go to first page when document changes
            DispatchQueue.main.async { // Ensure UI updates on main thread
                pdfView.goToFirstPage(nil)
                // First, set to fit width for better initial view
                pdfView.scaleFactor = pdfView.scaleFactorForSizeToFit
                // Then reset to 100% or a specific value if needed
                pdfView.scaleFactor = 1.0 
                zoomLevel = pdfView.scaleFactor // Update binding with actual scale
                pdfView.layoutDocumentView() // Ensure layout updates after scale change
            }
            // No need to set needsLayoutUpdate here as async block handles it
        } else if abs(pdfView.scaleFactor - zoomLevel) > 0.01 {
            // Self.logger.debug("External zoom change detected: \(zoomLevel)") // Debug print
            pdfView.scaleFactor = zoomLevel
            needsLayoutUpdate = true
        }

        // Re-apply display settings (could be optimized to check current values first)
        if pdfView.displayMode != .singlePageContinuous { 
            pdfView.displayMode = .singlePageContinuous
            needsLayoutUpdate = true
        }
        if !pdfView.displaysPageBreaks { 
            pdfView.displaysPageBreaks = true
            needsLayoutUpdate = true
        }
        // Ensure correct display direction
        if pdfView.displayDirection != .vertical {
            pdfView.displayDirection = .vertical
            needsLayoutUpdate = true
        }

        if needsLayoutUpdate {
            // Self.logger.debug("Requesting PDFView layout update") // Debug print
            pdfView.layoutDocumentView()
        }
    }

    // --- Configuration Helper ---
    private func configurePDFView(_ pdfView: PDFView) {
        pdfView.document = pdfDocument
        pdfView.displayMode = .singlePageContinuous // *** Ensure continuous scrolling ***
        pdfView.displaysPageBreaks = true // Show separation between pages
        pdfView.displayDirection = .vertical
        pdfView.autoScales = false // Controlled externally or by user
        pdfView.backgroundColor = NSColor.white // Use explicit white for reliable rendering
        pdfView.interpolationQuality = .high // Better rendering quality
        pdfView.maxScaleFactor = 8.0
        pdfView.minScaleFactor = 0.1

        // Disable unnecessary features for better performance
        pdfView.enableDataDetectors = false // Disable data detectors (like URLs)
        
        // Access underlying scroll view for better scroll behavior
        if let scrollView = pdfView.documentView?.enclosingScrollView {
            scrollView.allowsMagnification = true // Ensure pinch-to-zoom works
            scrollView.scrollerStyle = .overlay // Use modern overlay scrollers
        }

        // Set initial zoom
        pdfView.scaleFactor = zoomLevel
    }

    // --- Coordinator (Optional) ---
    // func makeCoordinator() -> Coordinator { Coordinator(self) }
    // class Coordinator: NSObject, PDFViewDelegate {
    //     var parent: EnhancedPDFKitView
    //     init(_ parent: EnhancedPDFKitView) { self.parent = parent }
    //     // Implement delegate methods like pdfViewPageChanged if needed
    // }
} 