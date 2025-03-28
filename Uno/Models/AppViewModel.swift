import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import os

@MainActor // Ensure UI updates are on the main thread
class AppViewModel: ObservableObject {

    // MARK: - Enums -

    enum Mode: String, CaseIterable, Identifiable, Hashable {
        case prompt = "Prompt"
        case pdf = "PDF"
        var id: String { self.rawValue }
    }

    enum ProcessingState: Equatable {
        case idle
        case scanning(String) // Indicate which folder is being scanned
        case processing(Double, String) // Progress (0-1) and current step description
        case error(String)
        case success(String) // Optional success message
        
        var isProcessing: Bool {
            switch self {
            case .scanning, .processing:
                return true
            default:
                return false
            }
        }
    }
    
    enum ViewState {
        case empty
        case filesPresent
    }
    
    struct SkippedItemInfo: Identifiable {
        let id = UUID()
        let name: String
        let reason: String
    }

    // MARK: - Published Properties -

    @Published var fileTree: [FileItem] = []
    @Published var currentMode: Mode = .prompt {
        didSet {
            if oldValue != currentMode && !fileTree.isEmpty {
                Task { await processFiles() }
            }
        }
    }
    @Published var processingState: ProcessingState = .idle
    @Published var criticalErrors: [String] = [] // Serious errors only
    @Published var viewState: ViewState = .empty
    @Published var skippedFilesInfo: [SkippedItemInfo] = []

    // Prompt Mode Specific
    @Published var generatedPrompt: String = ""
    @Published var promptMaxSizeMB: Double = 1.0 // Max size in MB for full inclusion
    @Published var includeTreeInPrompt: Bool = false

    // PDF Mode Specific
    @Published var generatedPDF: PDFDocument?

    // MARK: - Constants & Logger -
    private static let logger = Logger(subsystem: "me.nuanc.Uno", category: "AppViewModel")
    private let maxFileSizeForPromptNote: Int64 = 500 * 1024 * 1024 // 500MB absolute max to even *try* reading

    // MARK: - Computed Properties -
    
    // Get a flattened list of all file items
    var fileItemsList: [FileItem] {
        flattenTree(items: fileTree)
    }

    // MARK: - File Handling -

    func addUrls(_ urls: [URL]) {
        // Check if we can proceed with adding URLs
        if case .scanning = processingState { return }
        if case .processing = processingState { return }
        
        fileTree.removeAll() // Clear existing files before adding new ones
        viewState = .empty // Reset view state
        criticalErrors.removeAll()
        processingState = .scanning("Selected items...")

        Task { // Perform scanning asynchronously
            var newRootItems: [FileItem] = []
            for url in urls {
                if let item = await createFileItem(from: url) {
                    newRootItems.append(item)
                }
            }

            // Add new items to the tree
            fileTree = newRootItems
            
            // Sort the root tree alphabetically
            fileTree.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            if fileTree.isEmpty {
                processingState = .idle
                viewState = .empty
            } else {
                viewState = .filesPresent
                await processFiles()
            }
        }
    }

    private func createFileItem(from url: URL, isRoot: Bool = true) async -> FileItem? {
        // Basic security check / bookmark resolution might be needed here for sandbox
        // Assuming direct access for now
        do {
            let resourceValues = try url.resourceValues(forKeys: [.nameKey, .isDirectoryKey, .contentTypeKey, .fileSizeKey])
            let name = resourceValues.name ?? url.lastPathComponent
            let type = resourceValues.contentType
            let size = resourceValues.fileSize.map { Int64($0) } // Size in bytes

            if resourceValues.isDirectory == true {
                // It's a directory, scan its contents
                processingState = .scanning(url.lastPathComponent) // Update status
                var children: [FileItem] = []
                let enumerator = FileManager.default.enumerator(at: url,
                                                               includingPropertiesForKeys: [.nameKey, .isDirectoryKey, .contentTypeKey, .fileSizeKey],
                                                               options: [.skipsHiddenFiles, .skipsPackageDescendants])

                if let fileEnumerator = enumerator {
                    for case let fileURL as URL in fileEnumerator {
                         // Recursively create items for children, marking them as not root
                         // Stop scanning if state changes away from scanning
                        guard case .scanning = processingState else {
                            Self.logger.info("Scanning cancelled.")
                            return nil // Abort if state changed
                        }
                        if let childItem = await createFileItem(from: fileURL, isRoot: false) {
                            children.append(childItem)
                        }
                    }
                }
                // Sort children alphabetically
                 children.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                return FileItem(url: url, name: name, type: type, size: size, children: children, isExpanded: isRoot) // Expand root folders initially
            } else {
                // It's a file
                return FileItem(url: url, name: name, type: type, size: size, children: nil)
            }
        } catch {
            Self.logger.error("Error accessing file attributes for \(url.path): \(error.localizedDescription)")
            criticalErrors.append("Error accessing: \(url.lastPathComponent)")
            return nil
        }
    }

    func removeItem(id: UUID) {
         Self.logger.info("Attempting to remove item with ID: \(id.uuidString)")
         if let index = fileTree.firstIndex(where: { $0.id == id }) {
              let removed = fileTree.remove(at: index)
              Self.logger.info("Removed root item: \(removed.name)")
              // If removing the last item, clear results
              if fileTree.isEmpty {
                  clearAll()
              } else {
                   // Re-process after removal
                   Task { await processFiles() }
              }
         } else {
             Self.logger.warning("Could not find root item with ID \(id.uuidString) to remove.")
         }
     }

     func clearAll() {
         Self.logger.info("Clearing all files and results.")
         fileTree.removeAll()
         generatedPrompt = ""
         generatedPDF = nil
         criticalErrors.removeAll()
         skippedFilesInfo.removeAll()
         processingState = .idle
         viewState = .empty
     }

    // MARK: - Processing Logic -

    func processFiles() async {
         guard !fileTree.isEmpty else {
             Self.logger.info("No files in tree to process.")
             clearAll() // Ensure clean state
             return
         }

        // Check if we can proceed with processing
        if case .scanning = processingState { 
            Self.logger.warning("Ignoring process request while busy (scanning)")
            return 
        }
        if case .processing = processingState { 
            Self.logger.warning("Ignoring process request while busy (processing)")
            return
        }

         processingState = .processing(0, "Starting...")
         criticalErrors.removeAll()
         skippedFilesInfo.removeAll()
         generatedPrompt = ""
         generatedPDF = nil

         // Flatten the tree to get a list of selected files to process
         let selectedItems = flattenTree(items: fileTree).filter { $0.isSelected && !$0.isDirectory }
         let totalFilesToProcess = selectedItems.count
         guard totalFilesToProcess > 0 else {
             Self.logger.info("No files selected for processing.")
             processingState = .idle 
             return
         }

         Self.logger.info("Processing \(totalFilesToProcess) selected files for mode: \(self.currentMode.rawValue)")

         do {
             switch currentMode {
             case .prompt:
                 await generatePrompt(selectedItems: selectedItems)
             case .pdf:
                 await generatePDF(selectedItems: selectedItems)
             }

             if criticalErrors.isEmpty {
                 processingState = .success("Processing complete.")
                 Self.logger.info("Processing finished successfully.")
             } else {
                 processingState = .error("Processing completed with errors.")
                 Self.logger.warning("Processing finished with \(self.criticalErrors.count) errors.")
             }

         } catch is CancellationError {
             Self.logger.info("Processing cancelled.")
             processingState = .idle
         } catch {
             Self.logger.error("Unexpected error during processing: \(error.localizedDescription)")
             criticalErrors.append("An unexpected error occurred.")
             processingState = .error("Processing failed.")
         }
     }

     // MARK: - Prompt Generation -

     private func generatePrompt(selectedItems: [FileItem]) async {
         var promptOutput = ""
         let maxSizeBytes = Int64(promptMaxSizeMB * 1024 * 1024)

         // 1. Optionally add tree structure
         if includeTreeInPrompt {
             processingState = .processing(0, "Generating file tree...")
             promptOutput += "```text\n" // Use code block for structure
             promptOutput += generateTreeString(items: fileTree) // Generate from the full tree
             promptOutput += "```\n\n"
         }

         // 2. Process each selected file
         for (index, item) in selectedItems.enumerated() {
             // Check for cancellation
              guard case .processing = processingState else { return }

             let progress = Double(index + 1) / Double(selectedItems.count)
             processingState = .processing(progress, "Processing: \(item.name)")

             guard let fileSize = item.size else {
                 Self.logger.warning("Skipping file with unknown size: \(item.name)")
                 promptOutput += "[Note: \(item.name) - Unknown size]\n\n"
                 continue
             }

             // Check absolute max size
             guard fileSize <= maxFileSizeForPromptNote else {
                 Self.logger.warning("Skipping file larger than absolute max (\(fileSize / 1024 / 1024)MB): \(item.name)")
                 promptOutput += "[Skipped: \(item.name) - File exceeds maximum size limit of 500MB]\n\n"
                 continue
             }

             // Apply configurable size threshold
             if fileSize <= maxSizeBytes {
                 // Include full content
                 if let content = await readFileContent(item.url, item.type) {
                     promptOutput += "<\(item.name)>\n"
                     promptOutput += content
                     promptOutput += "\n</\(item.name)>\n\n"
                 } else {
                     // Error reading file
                     promptOutput += "[Error: \(item.name) - Could not read file content]\n\n"
                 }
             } else {
                 // Note the file instead of including content
                  Self.logger.info("File \(item.name) (\(fileSize / 1024 / 1024)MB) exceeds \(self.promptMaxSizeMB)MB threshold. Noting instead of including.")
                  promptOutput += "[Note: \(item.name) - Size \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)) exceeds inclusion threshold of \(promptMaxSizeMB)MB]\n\n"
             }
         }

         generatedPrompt = promptOutput.trimmingCharacters(in: .whitespacesAndNewlines)
     }

     private func readFileContent(_ url: URL, _ type: UTType?) async -> String? {
         // TODO: Add security scope handling if sandboxed
         do {
             if type?.conforms(to: .pdf) == true {
                 // Use non-main thread for potentially blocking PDF parsing
                 return await Task.detached {
                     guard let pdf = PDFDocument(url: url) else {
                         // Use a synchronous approach instead of MainActor
                         DispatchQueue.main.async {
                             Self.logger.warning("Could not open PDF: \(url.lastPathComponent)")
                             self.criticalErrors.append("Cannot read PDF: \(url.lastPathComponent)")
                         }
                         return nil
                     }
                     return pdf.string // Warning: can be memory intensive
                 }.value
             } else if type?.conforms(to: .text) == true || type?.conforms(to: .sourceCode) == true || type?.conforms(to: .data) == true {
                 // For text, source code, or even generic data, try reading as text
                 // Use non-main thread for file I/O
                 return await Task.detached {
                     do {
                         // Attempt UTF-8 first
                         if let content = try? String(contentsOf: url, encoding: .utf8) {
                             return content
                         }
                         // Fallback: Detect encoding (basic)
                         let data = try Data(contentsOf: url)
                         var detectedEncoding: String.Encoding = .utf8
                         
                         // Use a synchronous encoding detection approach
                         var nsString: NSString?
                         let detected = NSString.stringEncoding(for: data, encodingOptions: nil, convertedString: &nsString, usedLossyConversion: nil)
                         if detected != 0 {
                             detectedEncoding = String.Encoding(rawValue: detected)
                         }
                         
                         let content = String(data: data, encoding: detectedEncoding)
                         if content == nil {
                             // Use a synchronous approach instead of MainActor
                             DispatchQueue.main.async {
                                  Self.logger.warning("Could not decode file as text: \(url.lastPathComponent)")
                                  self.criticalErrors.append("Cannot decode as text: \(url.lastPathComponent)")
                             }
                         }
                         return content
                     } catch {
                         // Use a synchronous approach instead of MainActor
                         DispatchQueue.main.async {
                              Self.logger.error("Error reading file content \(url.lastPathComponent): \(error.localizedDescription)")
                              self.criticalErrors.append("Error reading: \(url.lastPathComponent)")
                         }
                         return nil
                     }
                 }.value
             } else {
                 Self.logger.warning("Unsupported file type for prompt content: \(url.lastPathComponent) (\(type?.description ?? "Unknown"))")
                 criticalErrors.append("Unsupported type for prompt: \(url.lastPathComponent)")
                 // Throw an error to make the catch block reachable
                 throw NSError(domain: "UnoErrorDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported file type"])
             }
         } catch {
             // This catch block is now reachable
             return nil
         }
     }

     // MARK: - PDF Generation -

     private func generatePDF(selectedItems: [FileItem]) async {
         let document = PDFDocument()
         skippedFilesInfo.removeAll()
         
         for (index, item) in selectedItems.enumerated() {
             // Check for cancellation
              guard case .processing = processingState else { return }

             let progress = Double(index + 1) / Double(selectedItems.count)
             processingState = .processing(progress, "Adding: \(item.name)")

             // TODO: Add security scope handling if sandboxed
              if let pages = await createPdfPagesForItem(item) {
                  for page in pages {
                      document.insert(page, at: document.pageCount)
                  }
              } else {
                  // Item was skipped, add to skip list
                  skippedFilesInfo.append(SkippedItemInfo(
                    name: item.name,
                    reason: "Could not convert to PDF format"
                  ))
              }
         }

         if document.pageCount > 0 {
             generatedPDF = document
         } else {
             if skippedFilesInfo.isEmpty && !selectedItems.isEmpty {
                 criticalErrors.append("No valid pages could be generated from selected files.")
             }
             generatedPDF = nil // Ensure it's nil if no pages added
         }
     }

    private func createPdfPagesForItem(_ item: FileItem) async -> [PDFPage]? {
        guard let type = item.type else {
            Self.logger.warning("Skipping PDF generation for unknown type: \(item.name)")
            criticalErrors.append("Unknown type for PDF: \(item.name)")
            return nil
        }

        // Use Task.detached for blocking operations
        return await Task.detached {
            var generatedPages: [PDFPage] = []

            let url = item.url // Assuming URL is accessible
            
            // Handle PDFs first (synchronous)
            if type.conforms(to: .pdf) {
                autoreleasepool {
                    if let sourceDoc = PDFDocument(url: url) {
                        for i in 0..<sourceDoc.pageCount {
                            if let page = sourceDoc.page(at: i)?.copy() as? PDFPage { // Important to COPY pages
                                generatedPages.append(page)
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            Self.logger.warning("Failed to load source PDF: \(item.name)")
                            self.criticalErrors.append("Cannot load source PDF: \(item.name)")
                        }
                    }
                }
            }
            // Handle images (requires Main thread for PDF creation)
            else if type.conforms(to: .image) {
                if let image = NSImage(contentsOf: url) {
                    // Create a Task to handle the PDF creation
                    var pageData: Data? = nil
                    
                    // Use Task rather than semaphore
                    await MainActor.run {
                        pageData = self.createPDFPageDataFromImage(image: image, title: item.name)
                    }
                    
                    if let realPageData = pageData,
                       let pdfDocument = PDFDocument(data: realPageData),
                       let page = pdfDocument.page(at: 0)?.copy() as? PDFPage {
                        generatedPages.append(page)
                    } else {
                        DispatchQueue.main.async {
                            Self.logger.warning("Failed to create PDF page from image: \(item.name)")
                            self.criticalErrors.append("Cannot convert image: \(item.name)")
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        Self.logger.warning("Failed to load image: \(item.name)")
                        self.criticalErrors.append("Cannot load image: \(item.name)")
                    }
                }
            }
            // Handle text content (requires async reading)
            else if type.conforms(to: .text) || type.conforms(to: .sourceCode) || type.conforms(to: .data) {
                // Create a future for reading the content
                let contentFuture = Task<String?, Error> { 
                    return await self.readFileContent(url, type) 
                }
                
                do {
                    // Await content reading (outside autoreleasepool)
                    let content = try await contentFuture.value
                    
                    if let realContent = content, !realContent.isEmpty {
                        // Create PDF using MainActor instead of semaphore
                        var pageData: Data? = nil
                        
                        await MainActor.run {
                            pageData = self.createPDFPageDataFromText(content: realContent, title: item.name)
                        }
                        
                        if let realPageData = pageData,
                           let pdfDocument = PDFDocument(data: realPageData),
                           let page = pdfDocument.page(at: 0)?.copy() as? PDFPage {
                            generatedPages.append(page)
                        } else {
                            DispatchQueue.main.async {
                                Self.logger.warning("Failed to create PDF page from text content: \(item.name)")
                                self.criticalErrors.append("Cannot convert text: \(item.name)")
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            Self.logger.warning("Failed to create PDF page from text content: \(item.name)")
                            self.criticalErrors.append("Cannot convert text: \(item.name)")
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        Self.logger.warning("Error processing text file: \(item.name)")
                        self.criticalErrors.append("Error processing: \(item.name)")
                    }
                }
            }
            // Handle unsupported types
            else {
                DispatchQueue.main.async {
                    Self.logger.warning("Unsupported file type for PDF generation: \(item.name)")
                    self.criticalErrors.append("Unsupported type for PDF: \(item.name)")
                }
            }
            
            // Wait a short time for any tasks to finish
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            
            return generatedPages.isEmpty ? nil : generatedPages
        }.value
    }

    // PDF Page Creation Helpers
    private func createPDFPageDataFromImage(image: NSImage, title: String) -> Data? {
        let pageBounds = CGRect(x: 0, y: 0, width: 595, height: 842) // A4
        let margin: CGFloat = 40
        let pdfData = NSMutableData()
        
        var mediaBox = pageBounds
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { 
            return nil 
        }

        context.beginPDFPage(nil)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(pageBounds)
        drawHeader(title: title, context: context, bounds: pageBounds, margin: margin)

        let imageSize = image.size
        let drawingRect = pageBounds.insetBy(dx: margin, dy: margin + 20)
        let aspectWidth = drawingRect.width / imageSize.width
        let aspectHeight = drawingRect.height / imageSize.height
        let aspectRatio = min(aspectWidth, aspectHeight)
        let scaledWidth = imageSize.width * aspectRatio
        let scaledHeight = imageSize.height * aspectRatio
        let imageOriginX = drawingRect.origin.x + (drawingRect.width - scaledWidth) / 2
        let imageOriginY = drawingRect.origin.y + (drawingRect.height - scaledHeight) / 2
        let targetRect = CGRect(x: imageOriginX, y: imageOriginY, width: scaledWidth, height: scaledHeight)

        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            context.draw(cgImage, in: targetRect)
        }

        context.endPDFPage()
        context.closePDF()

        return pdfData as Data
    }

    private func createPDFPageDataFromText(content: String, title: String) -> Data? {
        let pageBounds = CGRect(x: 0, y: 0, width: 595, height: 842) // A4
        let margin: CGFloat = 40
        let pdfData = NSMutableData()
        
        var mediaBox = pageBounds
        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { 
            return nil 
        }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 1.5
        paragraphStyle.paragraphSpacing = 6
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle
        ]
        let attributedString = NSAttributedString(string: content, attributes: attributes)

        context.beginPDFPage(nil)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(pageBounds)
        drawHeader(title: title, context: context, bounds: pageBounds, margin: margin)

        let textFrameRect = CGRect(x: margin, y: margin, width: pageBounds.width - 2 * margin, height: pageBounds.height - 2 * margin - 20)

        // Simple single-page drawing (will truncate)
        attributedString.draw(in: textFrameRect)

        // Proper multi-page requires CTFramesetter logic here, similar to FileProcessor refactor

        context.endPDFPage()
        context.closePDF()

        return pdfData as Data
    }

    private func drawHeader(title: String, context: CGContext, bounds: CGRect, margin: CGFloat) {
         let headerAttributes: [NSAttributedString.Key: Any] = [
             .font: NSFont.systemFont(ofSize: 9, weight: .light),
             .foregroundColor: NSColor.darkGray
         ]
         let headerString = NSAttributedString(string: title, attributes: headerAttributes)
         let headerHeight: CGFloat = 15
         let headerRect = CGRect(x: margin, y: bounds.height - margin - headerHeight + 5,
                                 width: bounds.width - 2 * margin, height: headerHeight)
         context.saveGState()
         context.textMatrix = .identity
         headerString.draw(in: headerRect)
         context.restoreGState()
         // Optional Line
         context.setStrokeColor(NSColor.lightGray.cgColor)
         context.setLineWidth(0.5)
         context.move(to: CGPoint(x: margin, y: bounds.height - margin - headerHeight))
         context.addLine(to: CGPoint(x: bounds.width - margin, y: bounds.height - margin - headerHeight))
         context.strokePath()
     }


    // MARK: - Helpers -

    // Flattens the tree into a list of items (pre-order traversal)
     private func flattenTree(items: [FileItem]) -> [FileItem] {
         var flattened: [FileItem] = []
         for item in items {
             flattened.append(item)
             if let children = item.children {
                 flattened.append(contentsOf: flattenTree(items: children))
             }
         }
         return flattened
     }

    // Generates ASCII tree string for selected items
    private func generateTreeString(items: [FileItem], prefix: String = "", isRoot: Bool = true) -> String {
        var output = ""
        for (index, item) in items.enumerated() {
             guard item.isSelected else { continue } // Only include selected items in the tree string

            let isLast = index == items.count - 1
            let connector = isRoot ? "" : (isLast ? "└── " : "├── ")
            let nameSuffix = item.isDirectory ? "/" : ""

            output += prefix + connector + item.name + nameSuffix + "\n"

            if let children = item.children, !children.isEmpty {
                let childPrefix = prefix + (isRoot ? "" : (isLast ? "    " : "│   "))
                output += generateTreeString(items: children, prefix: childPrefix, isRoot: false)
            }
        }
        return output
    }
} 