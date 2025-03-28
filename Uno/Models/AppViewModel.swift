import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import os
import Combine // For debouncing settings changes

@MainActor // Ensure UI updates are on the main thread
class AppViewModel: ObservableObject {

    // MARK: - Enums -

    enum Mode: String, CaseIterable, Identifiable, Hashable {
        case prompt = "Prompt"
        case pdf = "PDF"
        var id: String { self.rawValue }
    }

    enum ViewState {
        case empty
        case filesPresent
    }
    
    // Refined Processing State
    enum ProcessingState: Equatable {
        case idle
        case scanning(String)
        case preparing // Short state before processing starts
        case processing(Double, String) // Progress (0-1) and current step description
        case cancelling
        case error(String) // Critical error summary
        case success(String) // Optional success message
        
        var isProcessing: Bool {
            switch self {
            case .scanning, .processing, .preparing, .cancelling:
                return true
            default:
                return false
            }
        }
    }
    
    struct SkippedItemInfo: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let reason: String
    }

    // MARK: - Published Properties -

    @Published var fileTree: [FileItem] = []
    @Published var currentMode: Mode = .prompt {
        didSet {
            if oldValue != currentMode {
                Self.logger.info("Mode changed to \(self.currentMode.rawValue). Triggering reprocess.")
                // Don't clear files, just reprocess
                triggerProcessing()
            }
        }
    }
    @Published private(set) var viewState: ViewState = .empty
    @Published private(set) var processingState: ProcessingState = .idle
    @Published private(set) var criticalErrors: [String] = [] // Only critical errors

    // Prompt Mode Specific
    @Published var promptChunks: [String] = [] // *** For progressive loading ***
    @Published var generatedPrompt: String = "" // Keep final combined prompt if needed elsewhere
    @Published var promptMaxSizeMB: Double = 1.0
    @Published var includeTreeInPrompt: Bool = false

    // PDF Mode Specific
    @Published var generatedPDF: PDFDocument?
    @Published var skippedFilesInfo: [SkippedItemInfo] = [] // Info for PDF mode

    // MARK: - Private Properties -
    private static let logger = Logger(subsystem: "me.nuanc.Uno", category: "AppViewModel")
    private let maxFileSizeForPromptNote: Int64 = 500 * 1024 * 1024
    private var fileBookmarks: [URL: Data] = [:] // Store bookmarks keyed by original URL
    private var processingTask: Task<Void, Never>? = nil // To manage the main processing task
    private var settingsDebounceTimer: AnyCancellable?

    // MARK: - Computed Properties -
    
    // Get a flattened list of all file items
    var fileItemsList: [FileItem] {
        flattenTree(items: fileTree)
    }

    // MARK: - Initialization & Setup -
    init() {
        // Example: Debounce settings changes to avoid excessive reprocessing
        setupSettingsDebouncer()

        // Defer initial update check or make it manual
        // Task { await UpdateChecker.shared.checkForUpdates() } // Or use a shared instance
    }

    private func setupSettingsDebouncer() {
         // Combine pipeline to debounce promptMaxSizeMB and includeTreeInPrompt changes
         settingsDebounceTimer = Publishers.CombineLatest(
             $promptMaxSizeMB.debounce(for: .milliseconds(750), scheduler: RunLoop.main),
             $includeTreeInPrompt.debounce(for: .milliseconds(750), scheduler: RunLoop.main)
         )
         .sink { [weak self] _, _ in
             guard let self = self, self.viewState == .filesPresent else { return }
             Self.logger.debug("Settings debounced. Triggering reprocess.")
             self.triggerProcessing()
         }
     }

    // MARK: - File Handling (Robust Bookmarks & State) -

    func addUrls(_ urls: [URL]) {
        guard processingState == .idle || processingState == .success("") || processingState == .error("") else {
            Self.logger.warning("Ignoring add request while busy (\(String(describing: self.processingState)))")
            return
        }

        // Reset state before starting scan
        clearAll(keepFiles: false) // Clear previous results and errors
        processingState = .scanning("Preparing...")
        viewState = .empty // Show scanning progress over empty state initially if preferred

        Task { // Perform scanning asynchronously
            var newRootItems: [FileItem] = []
            var collectedBookmarks: [URL: Data] = [:] // Collect new bookmarks during scan

            for url in urls {
                 processingState = .scanning(url.lastPathComponent) // Update status
                 // Create bookmark IMMEDIATELY for dropped URLs if they don't have one
                 if fileBookmarks[url] == nil {
                     do {
                         let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                         collectedBookmarks[url] = bookmarkData // Store the new bookmark
                         Self.logger.debug("Created security bookmark for added URL: \(url.lastPathComponent)")
                     } catch {
                         Self.logger.error("Failed to create bookmark for \(url.lastPathComponent): \(error.localizedDescription). File may be inaccessible.")
                         criticalErrors.append("Permission Error: Cannot secure access for \(url.lastPathComponent).")
                         // Decide: Skip this URL entirely or try accessing without bookmark? Skipping is safer for Sandbox.
                         continue // Skip this URL
                     }
                 }

                 // Now scan using the URL (bookmark resolution will happen inside createFileItem)
                 if let item = await createFileItem(from: url, collectedBookmarks: &collectedBookmarks) {
                    newRootItems.append(item)
                }
                // Check if cancelled
                 guard processingState != .cancelling else {
                    Self.logger.info("Scanning cancelled.")
                    clearAll()
                    return
                }
            }

            // --- State Transition FIX ---
             // If cancelled during loop, state is already handled. Otherwise...
             if processingState != .cancelling {
                 // Update the main bookmark dictionary
                 self.fileBookmarks.merge(collectedBookmarks) { (_, new) in new }

                 // Merge new items (ensure no duplicates based on URL)
                 var currentUrls = Set(self.fileTree.map { $0.url })
                 for newItem in newRootItems {
                      if !currentUrls.contains(newItem.url) {
                          self.fileTree.append(newItem)
                          currentUrls.insert(newItem.url)
                      }
                 }
                 self.fileTree.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

                 if !self.fileTree.isEmpty {
                     self.viewState = .filesPresent
                     Self.logger.info("Scanning complete. Found \(self.fileTree.count) root items. Triggering processing.")
                     self.processingState = .preparing // Move to preparing state
                     triggerProcessing() // Automatically process after adding
                 } else {
                     Self.logger.warning("Scanning complete. No valid items found.")
                     // If critical errors occurred during scanning, show them
                     self.processingState = criticalErrors.isEmpty ? .idle : .error("Scanning failed for some items.")
                     self.viewState = .empty // Remain in empty state
                 }
             }
        }
    }

    // Modified to handle bookmark creation/passing during scan
    private func createFileItem(from url: URL, collectedBookmarks: inout [URL: Data], isRoot: Bool = true) async -> FileItem? {
        // 1. Ensure we have bookmark data for this URL before proceeding
         var bookmarkData = fileBookmarks[url] ?? collectedBookmarks[url]
         if bookmarkData == nil && !isRoot { // If child URL has no bookmark yet, try to create it
              do {
                  // Need access to parent first? This gets complex.
                  // Safer: Assume parent directory access grants child access temporarily,
                  // OR require explicit bookmark creation for children if needed (more robust).
                  // Let's try creating bookmark directly for child:
                  bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                  collectedBookmarks[url] = bookmarkData // Store it
                  Self.logger.debug("Created bookmark for child \(url.lastPathComponent) during scan.")
              } catch {
                   Self.logger.warning("Could not create bookmark for child \(url.lastPathComponent): \(error.localizedDescription). Skipping.")
                   criticalErrors.append("Permission Error: Cannot secure \(url.lastPathComponent)")
                   return nil
              }
         }

         // 2. Access the URL securely using the bookmark
         guard let currentBookmarkData = bookmarkData,
               let (scopedURL, accessStarted) = await secureAccess(bookmarkData: currentBookmarkData) else {
             Self.logger.error("Failed to secure access for \(url.lastPathComponent) during scan.")
             // Don't add to criticalErrors here, secureAccess already does
             return nil
         }
         defer { if accessStarted { scopedURL.stopAccessingSecurityScopedResource() } }

        // 3. Get resource values using the SCOPED URL
        do {
            let resourceValues = try scopedURL.resourceValues(forKeys: [.nameKey, .isDirectoryKey, .contentTypeKey, .fileSizeKey])
            let name = resourceValues.name ?? scopedURL.lastPathComponent
            let type = resourceValues.contentType
            let size = resourceValues.fileSize.map { Int64($0) }

            if resourceValues.isDirectory == true {
                var children: [FileItem] = []
                // Use FileManager enumerator on the SCOPED URL
                let enumerator = FileManager.default.enumerator(at: scopedURL,
                                                               includingPropertiesForKeys: [.nameKey, .isDirectoryKey, .contentTypeKey, .fileSizeKey],
                                                               options: [.skipsHiddenFiles, .skipsPackageDescendants])

                if let fileEnumerator = enumerator {
                    for case let fileURL as URL in fileEnumerator {
                        // Check for cancellation
                         guard processingState != .cancelling else { return nil }
                        // Recursively create items for children
                        if let childItem = await createFileItem(from: fileURL, collectedBookmarks: &collectedBookmarks, isRoot: false) {
                            children.append(childItem)
                        }
                    }
                }
                children.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                 // Use original URL for the FileItem ID/key, but store scoped info if needed? No, use original.
                 return FileItem(url: url, name: name, type: type, size: size, children: children, isExpanded: isRoot)
            } else {
                 return FileItem(url: url, name: name, type: type, size: size, children: nil)
            }
        } catch {
            Self.logger.error("Error reading attributes for scoped \(scopedURL.lastPathComponent): \(error.localizedDescription)")
            criticalErrors.append("Error Reading: \(scopedURL.lastPathComponent)")
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
                   Task { await triggerProcessing() }
              }
         } else {
             Self.logger.warning("Could not find root item with ID \(id.uuidString) to remove.")
         }
     }

     func clearAll(keepFiles: Bool = false) {
         Self.logger.info("Clearing results. Keep files: \(keepFiles)")
         cancelProcessing() // Cancel any ongoing task
         promptChunks = []
         generatedPrompt = ""
         generatedPDF = nil
         criticalErrors = []
         skippedFilesInfo = []
         if !keepFiles {
             fileTree = []
             fileBookmarks = [:]
             viewState = .empty
         }
         processingState = .idle
     }

    // MARK: - Processing Logic -

    private func generatePrompt(selectedItems: [FileItem]) async {
        let maxSizeBytes = Int64(promptMaxSizeMB * 1024 * 1024)
        var currentChunks: [String] = [] // Build locally first

        // 1. Optionally add tree structure
        if includeTreeInPrompt {
             // Check for cancellation before starting
            guard processingState != .cancelling else { return }
            processingState = .processing(0, "Generating file tree...")
            var treeString = "```text\n"
            treeString += generateTreeString(items: fileTree) // Use full tree
            treeString += "```\n\n"
            currentChunks.append(treeString)
            // Update immediately
             await MainActor.run { self.promptChunks = currentChunks }
        }

        // 2. Process each selected file
        for (index, item) in selectedItems.enumerated() {
            // Check for cancellation *before* processing each item
             guard processingState != .cancelling else { return }

            let progress = Double(index + 1) / Double(selectedItems.count)
            processingState = .processing(progress, item.name) // Update status *before* potential async work

            var chunkToAdd = ""

            guard let fileSize = item.size else {
                chunkToAdd = "[Skipped: \(item.name) - Unknown Size]\n\n"
                Self.logger.warning("Skipping \(item.name): Unknown size")
                // Maybe add to skippedFilesInfo even for prompt mode? Or just inline note.
                skippedFilesInfo.append(.init(name: item.name, reason: "Unknown file size"))
                currentChunks.append(chunkToAdd)
                await MainActor.run { self.promptChunks = currentChunks } // Update UI
                continue // Move to next item
            }

            guard fileSize <= maxFileSizeForPromptNote else {
                chunkToAdd = "[Skipped: \(item.name) - File Exceeds Max Limit (\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)))]\n\n"
                Self.logger.warning("Skipping \(item.name): Exceeds absolute limit")
                skippedFilesInfo.append(.init(name: item.name, reason: "File too large (\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)))"))
                currentChunks.append(chunkToAdd)
                await MainActor.run { self.promptChunks = currentChunks }
                continue
            }

            if fileSize <= maxSizeBytes {
                 if let content = await readFileContent(item) { // Pass full item
                     chunkToAdd = "<\(item.name)>\n\(content)\n</\(item.name)>\n\n"
                 } else {
                     // readFileContent logs critical errors and adds to criticalErrors
                     // Add an inline note indicating the failure for context
                     chunkToAdd = "[Skipped: \(item.name) - Error Reading File]\n\n"
                     skippedFilesInfo.append(.init(name: item.name, reason: "Error reading content"))
                 }
            } else {
                chunkToAdd = "[Note: \(item.name) - Exceeds \(String(format: "%.1f", promptMaxSizeMB)) MB Size Limit (\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)))]\n\n"
                Self.logger.info("\(item.name) exceeds threshold, noting instead of including.")
                skippedFilesInfo.append(.init(name: item.name, reason: "Exceeds size limit (\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)))"))
            }

            currentChunks.append(chunkToAdd)
             // Update the published chunks progressively
             await MainActor.run { self.promptChunks = currentChunks }

             // Optional small delay to allow UI updates if processing is very fast
             // try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

         // Combine final prompt *after* loop completes
         await MainActor.run {
             self.generatedPrompt = self.promptChunks.joined()
         }
    }

     // Modified to take FileItem, uses secureAccess helper
     private func readFileContent(_ item: FileItem) async -> String? {
         guard let (scopedURL, accessStarted) = await secureAccess(for: item.url) else {
             // Error logged by secureAccess
             return nil
         }
         defer { if accessStarted { scopedURL.stopAccessingSecurityScopedResource() } }

         let url = scopedURL // Use the securely accessed URL
         let type = item.type

         do {
             // Run blocking I/O on detached task
             return try await Task.detached {
                 if type?.conforms(to: .pdf) == true {
                     guard let pdf = PDFDocument(url: url) else { throw ReadError.pdfOpenFailed }
                     guard let content = pdf.string else { throw ReadError.pdfContentExtractionFailed }
                     return content // Warning: memory intensive
                 } else if type?.conforms(to: .text) == true || type?.conforms(to: .sourceCode) == true || type?.conforms(to: .data) == true {
                     // Try common encodings
                     if let content = try? String(contentsOf: url, encoding: .utf8) { return content }
                     let data = try Data(contentsOf: url)
                     var fallback: String.Encoding = .utf8
                     if let content = String(data: data, encoding: await Self.detectEncoding(data: data, fallback: &fallback)) { return content }
                     throw ReadError.decodingFailed
                 } else {
                     throw ReadError.unsupportedType
                 }
             }.value
         } catch {
             // Log specific error and add to criticalErrors on MainActor
             await MainActor.run {
                 let errorReason: String
                 switch error {
                 case ReadError.pdfOpenFailed, is ReadError where error as? ReadError == .pdfOpenFailed:
                     errorReason = "Cannot open source PDF"
                 case ReadError.decodingFailed, is ReadError where error as? ReadError == .decodingFailed:
                     errorReason = "Cannot decode content"
                 case ReadError.unsupportedType, is ReadError where error as? ReadError == .unsupportedType:
                     errorReason = "Unsupported type for PDF"
                 default: 
                     errorReason = "Error reading content (\(error.localizedDescription))"
                 }
                 Self.logger.error("Failed to read content for \(item.name): \(errorReason)")
                 self.criticalErrors.append("Read Error (\(item.name)): \(errorReason)")
             }
             return nil
         }
     }
     // Define ReadError enum inside ViewModel or globally
     enum ReadError: Error { case pdfOpenFailed, pdfContentExtractionFailed, decodingFailed, unsupportedType }

    // MARK: - PDF Generation (Robust Access & Skips) -

    @MainActor
    private func generatePDF(selectedItems: [FileItem]) async {
        guard !selectedItems.isEmpty else {
            Self.logger.debug("No items to generate PDF for.")
            processingState = .idle
            return
        }
        
        let document = PDFDocument()
        
        // Skip logic
        skippedFilesInfo = []
        
        for (index, item) in selectedItems.enumerated() {
            guard processingState != .cancelling else { return }
            
            let progress = Double(index) / Double(selectedItems.count)
            let step = "Processing \(item.name) (\(index + 1)/\(selectedItems.count))"
            processingState = .processing(progress, step)
            
            Self.logger.debug("Processing file for PDF: \(item.name)")
            
            // Security-scoped URL access wrapper
            var scopedURL: URL
            let accessStarted: Bool
            
            do {
                (scopedURL, accessStarted) = try await secureAccess(for: item.url) ?? (item.url, false)
            } catch {
                Self.logger.error("Access error for \(item.name): \(error.localizedDescription)")
                criticalErrors.append("Cannot access file: \(item.name)")
                skippedFilesInfo.append(.init(name: item.name, reason: "Access error"))
                continue
            }
            
            // PDF processing logic
            do {
                // Allow time for cancellation check & UI update
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms delay
                guard processingState != .cancelling else { return }
                
                // Validate each item has valid type/access
                guard let _ = try? scopedURL.resourceValues(forKeys: [.contentTypeKey]).contentType else {
                    Self.logger.error("Cannot determine type for \(item.name)")
                    if accessStarted { scopedURL.stopAccessingSecurityScopedResource() }
                    skippedFilesInfo.append(.init(name: item.name, reason: "Cannot determine file type"))
                    continue
                }
                
                // Perform PDF page creation off main thread
                let pagesResult = await Task.detached { // Explicitly detach
                    // Need access *within* the detached task
                    let url = scopedURL
                    let type = item.type
                    var generatedPages: [PDFPage] = []
                    
                    // Make sure we don't throw from within the autoreleasepool itself
                    do {
                        try autoreleasepool {
                            if type?.conforms(to: .pdf) == true {
                                if let sourceDoc = PDFDocument(url: url) {
                                    for i in 0..<sourceDoc.pageCount {
                                        if let page = sourceDoc.page(at: i)?.copy() as? PDFPage {
                                            generatedPages.append(page)
                                        }
                                    }
                                } else {
                                    throw ReadError.pdfOpenFailed
                                }
                            } else if type?.conforms(to: .image) == true {
                                if let image = NSImage(contentsOf: url),
                                   let page = self.createPDFPageFromImageNonisolated(image: image, title: item.name) {
                                    generatedPages.append(page)
                                } else {
                                    throw ReadError.decodingFailed
                                }
                            } else if type?.conforms(to: .text) == true || type?.conforms(to: .sourceCode) == true || type?.conforms(to: .data) == true {
                                do {
                                    let data = try Data(contentsOf: url)
                                    let fallback: String.Encoding = .utf8
                                    
                                    // Use a synchronous encoding detection here
                                    let detectedEncoding = {
                                        var nsString: NSString?
                                        let detected = NSString.stringEncoding(for: data, encodingOptions: nil, convertedString: &nsString, usedLossyConversion: nil)
                                        return detected != 0 ? String.Encoding(rawValue: detected) : fallback
                                    }()
                                    
                                    if let content = String(data: data, encoding: detectedEncoding), !content.isEmpty {
                                        if let page = self.createPDFPageFromTextNonisolated(content: content, title: item.name) {
                                            generatedPages.append(page)
                                        } else {
                                            throw ReadError.decodingFailed
                                        }
                                    } else if String(data: data, encoding: fallback) == nil {
                                        throw ReadError.decodingFailed
                                    }
                                } catch {
                                    throw error
                                }
                            } else {
                                throw ReadError.unsupportedType
                            }
                        }
                    } catch {
                        throw error
                    }
                    
                    return generatedPages
                }.result // Get result (success with pages or failure with error)
                
                // Stop accessing after detached task completes
                if accessStarted { scopedURL.stopAccessingSecurityScopedResource() }
                
                // Process result back on MainActor
                switch pagesResult {
                case .success(let pages):
                    if !pages.isEmpty {
                        for page in pages { document.insert(page, at: document.pageCount) }
                    } else {
                        // No pages generated, but no error thrown (e.g., empty text file) - potentially add skip note
                        Self.logger.debug("No PDF pages generated for \(item.name) (potentially empty or unsupported within type)")
                        // skippedFilesInfo.append(.init(name: item.name, reason: "No content generated")) // Optional skip note
                    }
                case .failure(let error):
                    let errorReason: String
                    if let readError = error as? ReadError {
                        switch readError {
                        case .pdfOpenFailed:
                            errorReason = "Cannot open source PDF"
                        case .decodingFailed:
                            errorReason = "Cannot decode content"
                        case .unsupportedType:
                            errorReason = "Unsupported type for PDF"
                        @unknown default:
                            errorReason = "Unknown error: \(readError)"
                        }
                    } else {
                        errorReason = "Error generating PDF page (\(error.localizedDescription))"
                    }
                    Self.logger.error("Failed to create PDF pages for \(item.name): \(errorReason)")
                    // Use skippedFilesInfo for non-critical PDF generation errors
                    skippedFilesInfo.append(.init(name: item.name, reason: errorReason))
                    // Don't add to criticalErrors unless it's a fundamental access issue handled by secureAccess
                }
            } catch {
                // Error outside the detached task
                Self.logger.error("Error in PDF processing for \(item.name): \(error.localizedDescription)")
                skippedFilesInfo.append(.init(name: item.name, reason: "Processing error: \(error.localizedDescription)"))
                // Stop resource access if still open from earlier error
                if accessStarted { scopedURL.stopAccessingSecurityScopedResource() }
            }
        }
        
        // Update final PDF state
        await MainActor.run {
            if document.pageCount > 0 {
                self.generatedPDF = document
            } else {
                self.generatedPDF = nil
                // If no pages AND no critical errors occurred, but skips happened, indicate via state?
                if criticalErrors.isEmpty && !skippedFilesInfo.isEmpty {
                    self.processingState = .error("PDF generation skipped some files.") // Use error state to show skip button
                } else if criticalErrors.isEmpty {
                    self.processingState = .error("No content found to generate PDF.") // Or idle?
                }
                // If critical errors exist, state is already handled
            }
        }
    }

    // MARK: - PDF Helpers -
    
    // Nonisolated version for use with detached tasks
    private nonisolated func createPDFPageFromImageNonisolated(image: NSImage, title: String) -> PDFPage? {
        let pageBounds = CGRect(x: 0, y: 0, width: 595, height: 842) 
        let margin: CGFloat = 40
        let pdfData = NSMutableData()
        
        var mediaBox = pageBounds  // Make it mutable
        guard let consumer = CGDataConsumer(data: pdfData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            return nil
        }
        
        // Fix beginPDFPage parameter
        context.beginPDFPage(nil)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(pageBounds)
        
        drawHeaderNonisolated(title: title, context: context, bounds: pageBounds, margin: margin)
        
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
        
        guard let pdfDocument = PDFDocument(data: pdfData as Data) else { return nil }
        return pdfDocument.page(at: 0)?.copy() as? PDFPage
    }
    
    // Nonisolated version for use with detached tasks
    private nonisolated func createPDFPageFromTextNonisolated(content: String, title: String) -> PDFPage? {
        let pageBounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 40
        let pdfData = NSMutableData()
        
        var mediaBox = pageBounds  // Make it mutable
        guard let consumer = CGDataConsumer(data: pdfData),
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
        
        // Fix beginPDFPage parameter
        context.beginPDFPage(nil)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(pageBounds)
        
        drawHeaderNonisolated(title: title, context: context, bounds: pageBounds, margin: margin)
        
        let textFrameRect = CGRect(x: margin, y: margin, width: pageBounds.width - 2 * margin, height: pageBounds.height - 2 * margin - 20)
        attributedString.draw(in: textFrameRect)
        
        context.endPDFPage()
        context.closePDF()
        
        guard let pdfDocument = PDFDocument(data: pdfData as Data) else { return nil }
        return pdfDocument.page(at: 0)?.copy() as? PDFPage
    }
    
    // Nonisolated version for use with detached tasks
    private nonisolated func drawHeaderNonisolated(title: String, context: CGContext, bounds: CGRect, margin: CGFloat) {
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
        
        context.setStrokeColor(NSColor.lightGray.cgColor)
        context.setLineWidth(0.5)
        context.move(to: CGPoint(x: margin, y: bounds.height - margin - headerHeight))
        context.addLine(to: CGPoint(x: bounds.width - margin, y: bounds.height - margin - headerHeight))
        context.strokePath()
    }
    
    // MainActor versions for UI context
    @MainActor private func createPDFPageFromImage(image: NSImage, title: String) -> PDFPage? {
        return createPDFPageFromImageNonisolated(image: image, title: title)
    }
    
    @MainActor private func createPDFPageFromText(content: String, title: String) -> PDFPage? {
        return createPDFPageFromTextNonisolated(content: content, title: title)
    }
    
    @MainActor private func drawHeader(title: String, context: CGContext, bounds: CGRect, margin: CGFloat) {
        drawHeaderNonisolated(title: title, context: context, bounds: bounds, margin: margin)
    }
    
    // MARK: - String Encoding Helper -
    
    private static func detectEncoding(data: Data, fallback: inout String.Encoding) async -> String.Encoding {
        var nsString: NSString?
        let detected = NSString.stringEncoding(for: data, encodingOptions: nil, convertedString: &nsString, usedLossyConversion: nil)
        if detected != 0 {
            fallback = String.Encoding(rawValue: detected)
            return fallback
        }
        return fallback
    }

    // MARK: - Processing Control (Cancellable Task) -

    func triggerProcessing() {
        cancelProcessing() // Cancel previous task if any

        guard !fileTree.isEmpty else {
            Self.logger.info("No files in tree to process.")
            clearAll(keepFiles: true) // Clear results but keep files
            return
        }
        guard processingState == .idle || processingState == .preparing || processingState == .success("") || processingState == .error("") else {
            Self.logger.warning("Ignoring triggerProcessing request while busy (\(String(describing: self.processingState)))")
            return
        }

        let selectedItems = flattenTree(items: fileTree).filter { $0.isSelected && !$0.isDirectory }
        guard !selectedItems.isEmpty else {
             Self.logger.info("No files selected for processing.")
             // Clear results, show appropriate message
             promptChunks = []
             generatedPrompt = ""
             generatedPDF = nil
             skippedFilesInfo = []
             processingState = .idle // Or maybe a specific "nothing selected" state?
             return
        }

        processingState = .preparing // Indicate prep
        criticalErrors.removeAll() // Clear errors for this run
        skippedFilesInfo.removeAll()
        promptChunks = [] // Clear previous chunks for prompt mode

        Self.logger.info("Starting processing task for \(selectedItems.count) items in mode \(self.currentMode.rawValue)")

        // Store and manage the processing task
        processingTask = Task {
             do {
                 // Short delay to allow UI to update to 'preparing' state
                 try await Task.sleep(nanoseconds: 50_000_000) // 50ms
                 guard processingState != .cancelling else { return }

                 processingState = .processing(0, "Starting...") // Now actually processing

                 switch currentMode {
                 case .prompt:
                     await generatePrompt(selectedItems: selectedItems)
                 case .pdf:
                     await generatePDF(selectedItems: selectedItems)
                 }

                 // Check if cancelled *during* processing
                 guard processingState != .cancelling else { return }

                 // Final state based on errors
                 if criticalErrors.isEmpty {
                      processingState = .success("Processing complete.")
                      Self.logger.info("Processing finished successfully.")
                 } else {
                      processingState = .error("Completed with \(criticalErrors.count) critical error(s).")
                      Self.logger.warning("Processing finished with errors.")
                 }

             } catch is CancellationError {
                 Self.logger.info("Processing task cancelled.")
                 // State is likely already .cancelling, reset fully
                  clearAll(keepFiles: true)
             } catch {
                 Self.logger.error("Unexpected error during processing task: \(error.localizedDescription)")
                 criticalErrors.append("An unexpected processing error occurred.")
                 processingState = .error("Processing failed unexpectedly.")
             }
        }
    }

    func cancelProcessing() {
        if let task = processingTask, !task.isCancelled {
            Self.logger.info("Cancelling processing task.")
            processingState = .cancelling
            task.cancel()
            processingTask = nil
             // Optionally reset state more fully here or let the cancelled task handle it
             // clearAll(keepFiles: true) might be too aggressive if user wants to retry
             // Resetting to idle after a short delay might be better
             DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                 if self.processingState == .cancelling {
                      self.processingState = .idle
                 }
             }
        }
    }

    // MARK: - Bookmark & Security Helpers (CRITICAL) -

    /// Attempts to secure access to a URL using stored bookmark data.
    /// Returns the scoped URL and a Bool indicating if access was started (needs stopping).
    private func secureAccess(for originalUrl: URL) async -> (URL, Bool)? {
         guard let bookmarkData = fileBookmarks[originalUrl] else {
             Self.logger.error("Access Error (\(originalUrl.lastPathComponent)): No bookmark data found. App may need restart or re-add file.")
             await MainActor.run { criticalErrors.append("Permission Error: Cannot find security info for \(originalUrl.lastPathComponent).") }
             return nil
         }
         return await secureAccess(bookmarkData: bookmarkData, originalUrlHint: originalUrl)
     }

    /// Low-level bookmark resolution and access start.
     private func secureAccess(bookmarkData: Data, originalUrlHint: URL? = nil) async -> (URL, Bool)? {
         var isStale = false
         do {
             // Resolve the bookmark
              let scopedURL = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)

             if isStale {
                  Self.logger.warning("Bookmark is stale for \(originalUrlHint?.lastPathComponent ?? "Unknown"). Attempting to refresh.")
                  // Try to create a new bookmark from the resolved URL
                  if let newBookmarkData = try? scopedURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil),
                     let originalUrl = originalUrlHint { // Need original URL to update dictionary
                       await MainActor.run { fileBookmarks[originalUrl] = newBookmarkData } // Update stored bookmark
                      Self.logger.info("Successfully refreshed stale bookmark.")
                  } else {
                       Self.logger.error("Failed to refresh stale bookmark.")
                       // Proceed with stale access, but log it
                  }
             }

             // Start accessing the resource
             let accessStarted = scopedURL.startAccessingSecurityScopedResource()
             if !accessStarted {
                 Self.logger.error("Access Error (\(originalUrlHint?.lastPathComponent ?? "Unknown")): Failed to start secure access even after resolving bookmark.")
                  await MainActor.run { criticalErrors.append("Permission Error: Cannot access \(originalUrlHint?.lastPathComponent ?? "file") after resolving.") }
                 return nil
             }
              Self.logger.debug("Successfully started secure access for \(scopedURL.lastPathComponent)")
             return (scopedURL, true) // Return scoped URL and flag that access started

         } catch {
             Self.logger.error("Bookmark Error (\(originalUrlHint?.lastPathComponent ?? "Unknown")): Failed to resolve bookmark: \(error.localizedDescription)")
             await MainActor.run { criticalErrors.append("Permission Error: Cannot resolve security info for \(originalUrlHint?.lastPathComponent ?? "file").") }
             // Handle specific bookmark errors if needed (e.g., file moved)
             return nil
         }
     }

    // MARK: - Tree Helpers -
    
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