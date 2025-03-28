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
                // Log BEFORE triggering processing
                Self.logger.info("Mode changed: \(oldValue.rawValue) -> \(self.currentMode.rawValue). Cache for new mode: \(self.cacheExists(for: self.currentMode) ? "Exists" : "Empty"). Triggering process check.")
                // Call the standard trigger, cache check will handle it
                triggerProcessing(forceReprocess: false) // DO NOT force reprocess on mode switch
            }
        }
    }
    @Published private(set) var viewState: ViewState = .empty
    @Published private(set) var processingState: ProcessingState = .idle
    @Published private(set) var criticalErrors: [String] = [] // Only critical errors
    @Published private(set) var isCancelled: Bool = false

    // Prompt Mode Specific
    @Published var promptChunks: [String] = [] // *** For progressive loading ***
    @Published var generatedPrompt: String = "" // Keep final combined prompt if needed elsewhere
    @Published var promptMaxSizeMB: Double = 1.0
    @Published var includeTreeInPrompt: Bool = false

    // PDF Mode Specific
    @Published var generatedPDF: PDFDocument?
    @Published var skippedFilesInfo: [SkippedItemInfo] = [] // Info for PDF mode
    
    // Store results per mode to avoid reprocessing if possible
    private var promptResultCache: (chunks: [String], combined: String)?
    private var pdfResultCache: PDFDocument?
    private var skipInfoCache: [SkippedItemInfo]?

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
        Self.logger.info("addUrls called with \(urls.count) URLs.")
        guard processingState == .idle || processingState == .success("") || processingState == .error("") else {
            Self.logger.warning("Ignoring add request while busy (\(String(describing: self.processingState)))")
            return
        }

        // *** Explicitly clear results and caches BEFORE scanning ***
        Self.logger.info("Clearing previous results and caches before adding new files.")
        // Cancel any lingering task first
        isCancelled = true
        if let task = processingTask, !task.isCancelled {
            Self.logger.notice("Cancelling active processingTask before adding files.")
            task.cancel()
        }
        
        // Clear all result caches
        promptChunks = []; generatedPrompt = ""; generatedPDF = nil
        criticalErrors = []; skippedFilesInfo = []
        promptResultCache = nil; pdfResultCache = nil; skipInfoCache = nil
        // Don't clear fileTree or fileBookmarks here - we're adding to them
        
        isCancelled = false // Reset cancellation flag after clearing
        processingState = .scanning("Preparing...")
        viewState = .empty // Show scanning progress over empty state initially

        Task { // Perform scanning asynchronously
            var newRootItems: [FileItem] = []
            var collectedBookmarks: [URL: Data] = [:] // Collect new bookmarks during scan
            Self.logger.debug("Starting file/folder scan.")
            
            for url in urls {
                 guard !isCancelled else { 
                     Self.logger.info("Scan cancelled during loop."); 
                     break 
                 }
                 
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
                         // Skip this URL if we can't bookmark it
                         continue
                     }
                 }

                 // Now scan using the URL
                 if let item = await createFileItem(from: url, collectedBookmarks: &collectedBookmarks) {
                    newRootItems.append(item)
                }
                
                // Check if cancelled
                 guard !isCancelled else {
                    Self.logger.info("Scanning cancelled.")
                    clearAll()
                    return
                }
            }
            
            Self.logger.debug("Finished file/folder scan.")

            // --- State Transition ---
             guard !isCancelled else { // Check flag again before final state update
                  Self.logger.info("Scan was cancelled before state update.")
                  // Don't try to manage state here, just return and let clearAll handle it
                  return
             }

             // Update the main bookmark dictionary
             self.fileBookmarks.merge(collectedBookmarks) { (_, new) in new }

             // Replace existing tree with new items for simplicity and consistency
             Self.logger.info("Replacing existing file tree with newly scanned items.")
             self.fileTree = newRootItems
             self.fileTree.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

             if !self.fileTree.isEmpty {
                 self.viewState = .filesPresent
                 Self.logger.info("Scanning complete. Found \(self.fileTree.count) root items. Triggering processing.")
                 self.processingState = .preparing // Move to preparing state
                 triggerProcessing(forceReprocess: true) // Always reprocess after adding new files
             } else {
                 Self.logger.warning("Scanning complete. No valid items found.")
                 // If critical errors occurred during scanning, show them
                 self.processingState = criticalErrors.isEmpty ? .idle : .error("Scanning failed for some items.")
                 self.viewState = .empty // Remain in empty state
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
               let (scopedURL, accessStarted) = await secureAccess(bookmarkData: currentBookmarkData, originalUrlHint: url) else {
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
                   triggerProcessing()
              }
         } else {
             Self.logger.warning("Could not find root item with ID \(id.uuidString) to remove.")
         }
     }

     func clearAll(keepFiles: Bool = false) {
         // Log entry *before* any action
         Self.logger.info("clearAll requested. Keep files: \(keepFiles). Current state: \(String(describing: self.processingState))")

         // 1. Signal Cancellation and block new processing *immediately*
         isCancelled = true // Set flag FIRST
         processingState = .cancelling // Set state to prevent new triggers

         // 2. Cancel the main processing task (if running)
         if let task = processingTask, !task.isCancelled {
             Self.logger.notice("Cancelling active processingTask.")
             task.cancel()
             // Don't nil out processingTask here yet, let it finish/cancel naturally
         } else {
             Self.logger.info("No active processingTask to cancel.")
         }

         // 3. Use a short, explicit delay on MainActor to allow async tasks to potentially observe the flag.
         // This is a pragmatic approach; true synchronization is much harder.
         Task {
              try? await Task.sleep(nanoseconds: 150_000_000) // 150ms delay

              // 4. *After* delay, reset all state properties, guarded by the flag
              // If something else reset the flag (e.g., new addUrls), abort clear.
              guard self.isCancelled && self.processingState == .cancelling else {
                  Self.logger.warning("ClearAll aborted, cancellation flag or state changed during delay.")
                  // Might need to reset isCancelled/processingState if stuck in cancelling
                  if self.processingState == .cancelling { self.processingState = .idle }
                  self.isCancelled = false
                  return
              }

              Self.logger.info("Proceeding with state reset after cancellation delay.")
              self.promptChunks = []; self.generatedPrompt = ""; self.generatedPDF = nil
              self.criticalErrors = []; self.skippedFilesInfo = []
              self.promptResultCache = nil; self.pdfResultCache = nil; self.skipInfoCache = nil

              if !keepFiles {
                  self.fileTree = []; self.fileBookmarks = [:]
                  self.viewState = .empty
                  Self.logger.info("Cleared files and bookmarks.")
              } else {
                  self.viewState = self.fileTree.isEmpty ? .empty : .filesPresent
              }

              // 5. Final state reset
              self.processingState = .idle
              self.isCancelled = false // Reset flag *last*
              self.processingTask = nil // Clear task reference *after* ensuring it was cancelled/finished
              Self.logger.info("ClearAll complete. Final state: idle, ViewState: \(String(describing: self.viewState))")
         }
     }

    // MARK: - Processing Logic -

    private func generatePrompt(selectedItems: [FileItem]) async -> (chunks: [String], combined: String) {
        let maxSizeBytes = Int64(promptMaxSizeMB * 1024 * 1024)
        var currentChunks: [String] = [] // Build locally first

        // 1. Optionally add tree structure
        if includeTreeInPrompt {
             // Check for cancellation before starting
            guard processingState != .cancelling else { return ([], "") }
            processingState = .processing(0, "Generating file tree...")
            var treeString = "<fileTree>\n"
            treeString += generateTreeString(items: fileTree) // Use full tree
            treeString += "</fileTree>\n\n"
            currentChunks.append(treeString)
            // Update immediately
             await MainActor.run { self.promptChunks = currentChunks }
        }

        // 2. Process each selected file
        for (index, item) in selectedItems.enumerated() {
            // Check for cancellation *before* processing each item
             guard processingState != .cancelling else { return (currentChunks, currentChunks.joined()) }

            let progress = Double(index + 1) / Double(selectedItems.count)
            processingState = .processing(progress, item.name) // Update status *before* potential async work

            var chunkToAdd = ""

            guard let fileSize = item.size else {
                chunkToAdd = "[Skipped: \(item.name) - Could not determine file size]\n\n"
                Self.logger.warning("Skipping \(item.name): Unknown size")
                skippedFilesInfo.append(.init(name: item.name, reason: "Unknown file size"))
                currentChunks.append(chunkToAdd)
                await MainActor.run { self.promptChunks = currentChunks } // Update UI
                continue // Move to next item
            }

            guard fileSize <= maxFileSizeForPromptNote else {
                chunkToAdd = "[Skipped: \(item.name) - File size (\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))) exceeds maximum processing limit]\n\n"
                Self.logger.warning("Skipping \(item.name): Exceeds absolute limit")
                skippedFilesInfo.append(.init(name: item.name, reason: "Exceeds processing limit (\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)))"))
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
                     chunkToAdd = "[Skipped: \(item.name) - Failed to read or decode content]\n\n"
                     skippedFilesInfo.append(.init(name: item.name, reason: "Content read/decode failed"))
                 }
            } else {
                chunkToAdd = "[Note: \(item.name) - Size (\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))) exceeds \(String(format: "%.1f", promptMaxSizeMB)) MB limit; Content omitted]\n\n"
                Self.logger.info("\(item.name) exceeds threshold, noting instead of including.")
                skippedFilesInfo.append(.init(name: item.name, reason: "Exceeds size limit (\(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)))"))
            }

            currentChunks.append(chunkToAdd)
             // Update the published chunks progressively
             await MainActor.run { self.promptChunks = currentChunks }
        }

         // Combine final prompt *after* loop completes
         let combined = currentChunks.joined()
         await MainActor.run { self.generatedPrompt = combined }
         return (currentChunks, combined)
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
                 case ReadError.pdfOpenFailed:
                     errorReason = "Cannot open source PDF"
                 case ReadError.decodingFailed:
                     errorReason = "Cannot decode content"
                 case ReadError.unsupportedType:
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

    // MARK: - PDF Generation (Fix Detached Task & Text Rendering) -
    
    private func generatePDF(selectedItems: [FileItem]) async -> (pdf: PDFDocument?, skips: [SkippedItemInfo]) {
        let document = PDFDocument()
        var currentSkippedInfo: [SkippedItemInfo] = []

        Self.logger.info("Starting PDF generation for \(selectedItems.count) items")

        for (index, item) in selectedItems.enumerated() {
            // Check cancellation flag frequently
            guard !isCancelled else { 
                Self.logger.info("PDF generation cancelled during processing at item \(index+1)/\(selectedItems.count): \(item.name)")
                break 
            }
            
            let progress = Double(index + 1) / Double(selectedItems.count)
            // Only update state if not cancelled
            if !isCancelled {
                processingState = .processing(progress, item.name)
            }

            Self.logger.debug("Processing item \(index+1)/\(selectedItems.count): \(item.name), type: \(item.type?.description ?? "unknown")")

            guard let (scopedURL, accessStarted) = await secureAccess(for: item.url) else {
                Self.logger.error("Failed to secure access for PDF processing: \(item.name)")
                currentSkippedInfo.append(.init(name: item.name, reason: "Permission/Access Error"))
                continue
            }

            // --- Detached Task with Additional Logging ---
            Self.logger.debug("Starting detached task for PDF processing of \(item.name)")
            let pagesResult: Result<[PDFPage], Error> = await Task.detached {
                let url = scopedURL // Use the URL already accessed
                let type = item.type // Capture necessary info
                let itemName = item.name // Capture name for error logging
                var generatedPages: [PDFPage] = []
                
                Self.logger.debug("In detached task: Processing \(itemName), type: \(type?.description ?? "unknown")")
                
                do {
                    try autoreleasepool {
                        if type?.conforms(to: .pdf) == true {
                            Self.logger.debug("Processing PDF file: \(itemName)")
                            if let sourceDoc = PDFDocument(url: url) {
                                Self.logger.debug("PDF opened successfully: \(itemName), \(sourceDoc.pageCount) pages")
                                for i in 0..<sourceDoc.pageCount {
                                    if let page = sourceDoc.page(at: i)?.copy() as? PDFPage {
                                        generatedPages.append(page)
                                    }
                                }
                                Self.logger.debug("Copied \(generatedPages.count) pages from PDF: \(itemName)")
                            } else {
                                Self.logger.error("Failed to open PDF file: \(itemName)")
                                throw ReadError.pdfOpenFailed
                            }
                        } else if type?.conforms(to: .image) == true {
                            Self.logger.debug("Processing image file: \(itemName)")
                            if let image = NSImage(contentsOf: url),
                               let page = self.createPDFPageFromImageNonisolated(image: image, title: itemName) {
                                generatedPages.append(page)
                                Self.logger.debug("Successfully created PDF page from image: \(itemName)")
                            } else {
                                Self.logger.error("Failed to create PDF from image: \(itemName)")
                                throw ReadError.decodingFailed
                            }
                        } else if type?.conforms(to: .text) == true || type?.conforms(to: .sourceCode) == true || type?.conforms(to: .data) == true {
                            Self.logger.debug("Processing text file: \(itemName)")
                            do {
                                let data = try Data(contentsOf: url)
                                Self.logger.debug("Read \(data.count) bytes from text file: \(itemName)")
                                
                                var fallback: String.Encoding = .utf8
                                
                                // Use a synchronous encoding detection here
                                let detectedEncoding = {
                                    var nsString: NSString?
                                    let detected = NSString.stringEncoding(for: data, encodingOptions: nil, convertedString: &nsString, usedLossyConversion: nil)
                                    return detected != 0 ? String.Encoding(rawValue: detected) : fallback
                                }()
                                
                                Self.logger.debug("Detected encoding for \(itemName): \(detectedEncoding)")
                                
                                guard let content = String(data: data, encoding: detectedEncoding), !content.isEmpty else {
                                    // Empty content or decoding failed, don't add page
                                    Self.logger.warning("Empty content or decoding failed for \(itemName)")
                                    if String(data: data, encoding: fallback) == nil { 
                                        Self.logger.error("Failed to decode content with fallback encoding for \(itemName)")
                                        throw ReadError.decodingFailed 
                                    }
                                    return generatedPages // Return empty array for empty content
                                }
                                
                                Self.logger.debug("Creating PDF pages from text for \(itemName) (\(content.count) chars)")
                                let textPages = self.createPDFPagesFromText(content: content, title: itemName)
                                Self.logger.debug("Created \(textPages.count) pages from text content for \(itemName)")
                                generatedPages.append(contentsOf: textPages)
                            } catch let fileError {
                                Self.logger.error("Error reading file content for \(itemName): \(fileError.localizedDescription)")
                                throw fileError
                            }
                        } else {
                            Self.logger.warning("Unsupported file type for \(itemName): \(type?.description ?? "unknown")")
                            throw ReadError.unsupportedType
                        }
                        
                        Self.logger.debug("Finished processing \(itemName) in autoreleasepool, generated \(generatedPages.count) pages")
                        return generatedPages
                    } // End autoreleasepool
                    
                    return generatedPages
                } catch let processingError {
                    Self.logger.error("Error in detached processing for \(itemName): \(processingError.localizedDescription)")
                    throw processingError
                }
            }.result

            if accessStarted { 
                scopedURL.stopAccessingSecurityScopedResource() 
                Self.logger.debug("Stopped security-scoped resource access for \(item.name)")
            }

            // Check cancellation flag before processing result
            guard !isCancelled else { 
                Self.logger.info("PDF generation cancelled after detached task completed for \(item.name)")
                break 
            }

            // Process result
            switch pagesResult {
            case .success(let pages):
                if !pages.isEmpty { 
                    pages.forEach { document.insert($0, at: document.pageCount) }
                    Self.logger.info("Added \(pages.count) pages to PDF document from \(item.name)")
                } else { 
                    Self.logger.warning("No pages generated for \(item.name), adding to skipped items")
                    currentSkippedInfo.append(.init(name: item.name, reason: "Empty or no content")) 
                }
            case .failure(let error):
                let reason = Self.reasonString(for: error)
                Self.logger.error("Failed to process \(item.name) for PDF: \(reason)")
                currentSkippedInfo.append(.init(name: item.name, reason: reason))
                if !(error is ReadError) { 
                    await MainActor.run { criticalErrors.append("PDF Error (\(item.name)): \(reason)") } 
                }
            }
        } // End loop

        // Check cancellation one last time before final update
        let finalPDF = !isCancelled && document.pageCount > 0 ? document : nil
        let finalSkips = isCancelled ? [] : currentSkippedInfo

        Self.logger.info("PDF generation complete: \(document.pageCount) total pages, \(currentSkippedInfo.count) skipped items")

        await MainActor.run {
            // Only update if not cancelled during the processing loop
            if !self.isCancelled {
                self.generatedPDF = finalPDF
                self.skippedFilesInfo = finalSkips
            }
        }
        
        // Return results for caching
        return (finalPDF, finalSkips)
    }

    // Helper to create reason string from error
    private static func reasonString(for error: Error) -> String {
        switch error {
        case ReadError.pdfOpenFailed: return "Cannot open source PDF"
        case ReadError.pdfContentExtractionFailed: return "Cannot extract PDF text"
        case ReadError.decodingFailed: return "Cannot decode content"
        case ReadError.unsupportedType: return "Unsupported file type"
        default: return "Processing Error (\(error.localizedDescription.prefix(50))...)" // Truncate long descriptions
        }
    }

    // --- Refactor createPDFPagesFromText to rigorously fix coordinate system issues for PDF text rendering ---
    private nonisolated func createPDFPagesFromText(content: String, title: String) -> [PDFPage] {
        // Start with an empty array of pages
        var pdfPages: [PDFPage] = []

        // Define page size (US Letter)
        let pageBounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 40

        // Log entry for debugging text rendering
        Self.logger.debug("createPDFPagesFromText called for '\(title)'")

        let attributes = Self.pdfTextAttributes()
        let attributedString = NSAttributedString(string: content, attributes: attributes)
        
        // Check if string is empty after creation
        guard attributedString.length > 0 else {
             Self.logger.warning("Attributed string length is zero for '\(title)', skipping PDF page creation.")
             return []
        }
        
        let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
        var currentPosition = 0
        var pageIndex = 0

        while currentPosition < attributedString.length {
            pageIndex += 1
            // Log page creation attempt
            Self.logger.debug("Creating PDF Page \(pageIndex) for '\(title)' starting at pos \(currentPosition)")

            let pdfData = NSMutableData()
            guard let consumer = CGDataConsumer(data: pdfData) else { 
                Self.logger.error("PDF Consumer creation failed for '\(title)'")
                break 
            }
                  
            var mediaBox = pageBounds  // Make it mutable
            guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
                Self.logger.error("PDF Context creation failed (Page \(pageIndex)) for '\(title)'")
                break
            }

            context.beginPDFPage(nil)
            
            // Fill background first
            context.setFillColor(NSColor.white.cgColor)
            context.fill(pageBounds)

            // --- Draw Header (Unflipped Coords) ---
            // Use the original drawHeader expecting top-left origin
            let headerHeight: CGFloat = 15
            let headerY = pageBounds.height - margin - headerHeight
            let headerRect = CGRect(x: margin, y: headerY, 
                                   width: pageBounds.width - 2 * margin, 
                                   height: headerHeight)
            
            // Header properties
            let headerAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .light),
                .foregroundColor: NSColor.darkGray
            ]
            let headerString = NSAttributedString(string: "\(title) (Page \(pageIndex))", attributes: headerAttributes)
            
            // Draw header directly without flipping
            context.saveGState()
            headerString.draw(in: headerRect)
            context.restoreGState()
            
            // Draw line below header
            context.setStrokeColor(NSColor.lightGray.cgColor)
            context.setLineWidth(0.5)
            context.move(to: CGPoint(x: margin, y: headerY - 2))
            context.addLine(to: CGPoint(x: pageBounds.width - margin, y: headerY - 2))
            context.strokePath()

            // --- Flip *ONLY* for CoreText Frame ---
            context.saveGState() // Save before flip
            context.textMatrix = .identity // Reset text matrix IMPORTANT
            context.translateBy(x: 0, y: pageBounds.height) // Move origin to top-left
            context.scaleBy(x: 1.0, y: -1.0) // Flip the Y-axis

            // --- Calculate text frame rect in flipped coordinates ---
            let textTopY = margin + headerHeight + 5 // Y position for text start (from top)
            let textBottomY = pageBounds.height - margin // Y position for text end (from top)
            let textAvailableHeight = textBottomY - textTopY

            // The flippedTextOriginY measures from bottom of page to text start
            let flippedTextOriginY = pageBounds.height - textBottomY
            let flippedTextFrameRect = CGRect(
                x: margin, 
                y: flippedTextOriginY, 
                width: pageBounds.width - 2 * margin,
                height: textAvailableHeight
            )

            Self.logger.debug("PDF page \(pageIndex) text frame: x=\(flippedTextFrameRect.origin.x), y=\(flippedTextFrameRect.origin.y), width=\(flippedTextFrameRect.width), height=\(flippedTextFrameRect.height)")

            // Create path for CoreText
            let path = CGPath(rect: flippedTextFrameRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(currentPosition, 0), path, nil)

            // Log frame details
            let frameRange = CTFrameGetStringRange(frame)
            Self.logger.debug("PDF page \(pageIndex): CTFrame created, full range: \(frameRange.location)-\(frameRange.location + frameRange.length)")

            // Draw text in FLIPPED coordinate system
            CTFrameDraw(frame, context)

            // Restore original state (unflip)
            context.restoreGState()
            
            context.endPDFPage()
            context.closePDF()

            // Create page object
            if let pdfDoc = PDFDocument(data: pdfData as Data), let page = pdfDoc.page(at: 0)?.copy() as? PDFPage {
                pdfPages.append(page)
                Self.logger.debug("PDF page \(pageIndex) successfully added.")
            } else {
                Self.logger.warning("PDFPage creation failed for '\(title)' page \(pageIndex)")
            }

            // Update position
            let visibleRange = CTFrameGetVisibleStringRange(frame) // Get range that *actually fit*
            Self.logger.debug("PDF page \(pageIndex): Visible range: \(visibleRange.location)-\(visibleRange.location + visibleRange.length), Length drawn: \(visibleRange.length)")
            
            currentPosition += visibleRange.length
            if visibleRange.length == 0 && currentPosition < attributedString.length {
                // Breakout if we're in a rendering loop with zero progress
                Self.logger.error("CTFrame zero length draw detected for '\(title)' page \(pageIndex) but more content remains. Breaking out.")
                // Add skip info
                Task { @MainActor in 
                    self.skippedFilesInfo.append(.init(name: title, reason: "Text rendering error (page \(pageIndex))")) 
                }
                break
            }
        }
        
        Self.logger.debug("Finished PDF page creation for '\(title)', generated \(pdfPages.count) pages.")
        return pdfPages
    }

    // Helper method for PDF text attributes
    private static nonisolated func pdfTextAttributes() -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 1.5
        return [
            .font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.black,
            .paragraphStyle: paragraphStyle
        ]
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

    // MARK: - Processing Control (Cancellation Check Refined) -

    func triggerProcessing(forceReprocess: Bool = false) {
        // Check isCancelled flag early
        guard !isCancelled else {
            Self.logger.info("Ignoring triggerProcessing because cancellation is pending.")
            return
        }

        // Check existing task status
        guard processingTask == nil || processingTask?.isCancelled == true else {
            Self.logger.warning("Processing task already running or finishing.")
            return
        }
        
        // Reset cancellation flag at the START of a new trigger
        isCancelled = false

        guard !fileTree.isEmpty else { 
            Self.logger.info("TriggerProcessing skipped: File tree empty.")
            clearAll(keepFiles: true) // Clear results but keep files
            return
        }
        
        guard processingState == .idle || processingState == .preparing || 
              processingState == .success("") || processingState == .error("") else {
            Self.logger.warning("Ignoring triggerProcessing request in state: \(String(describing: self.processingState))")
            return
        }

        let selectedItems = fileItemsList.filter { $0.isSelected && !$0.isDirectory }
        guard !selectedItems.isEmpty else {
            Self.logger.info("TriggerProcessing skipped: No items selected.")
            // Clear results, but keep the file tree
            promptChunks = []
            generatedPrompt = ""
            generatedPDF = nil
            skippedFilesInfo = []
            processingState = .idle
            return
        }

        // --- Cache Check with Detailed Logging ---
        var useCache = false
        if !forceReprocess {
            switch currentMode {
            case .prompt:
                if let cache = promptResultCache {
                    Self.logger.info("Using cached prompt results for \(selectedItems.count) items.")
                    // Restore state from cache
                    self.promptChunks = cache.chunks
                    self.generatedPrompt = cache.combined
                    self.skippedFilesInfo = [] // Skips are typically inline for prompt mode
                    self.criticalErrors = [] // Assume cache means no critical errors
                    self.processingState = .success("Loaded cached prompt.")
                    useCache = true
                } else {
                    Self.logger.info("No prompt cache available, will generate new results.")
                }
            case .pdf:
                if let cache = pdfResultCache {
                    Self.logger.info("Using cached PDF results for \(selectedItems.count) items (\(cache.pageCount) pages).")
                    // Restore state from cache
                    self.generatedPDF = cache
                    self.skippedFilesInfo = skipInfoCache ?? []
                    self.criticalErrors = []
                    self.processingState = .success("Loaded cached PDF.")
                    useCache = true
                } else {
                    Self.logger.info("No PDF cache available, will generate new results.")
                }
            }
        } else {
            Self.logger.info("Force reprocessing requested, ignoring cache.")
        }

        // If cache was used, exit early
        guard !useCache else { return }

        // --- Setup for New Processing Run ---
        Self.logger.info("Starting new processing run for \(selectedItems.count) items in mode \(self.currentMode.rawValue).")
        
        // Clear previous results based on mode
        promptChunks = []
        generatedPrompt = ""
        generatedPDF = nil
        criticalErrors = []
        skippedFilesInfo = []
        
        // Clear specific cache being regenerated
        if currentMode == .prompt {
            promptResultCache = nil
        } else {
            pdfResultCache = nil
            skipInfoCache = nil
        }
        
        processingState = .preparing

        processingTask = Task {
            do {
                try await Task.sleep(nanoseconds: 50_000_000) // Brief delay to allow UI to update
                
                // Check cancellation after delay
                guard !isCancelled else { 
                    Self.logger.info("Processing cancelled after initial delay.")
                    throw CancellationError() 
                }
                
                processingState = .processing(0, "Starting...")

                // --- Perform Actual Work ---
                var finalState: ProcessingState = .idle // Determine final state locally
                
                switch currentMode {
                case .prompt:
                    let result = await generatePrompt(selectedItems: selectedItems)
                    
                    // Check cancellation *before* cache update
                    guard !isCancelled else { 
                        Self.logger.info("Processing cancelled before storing prompt cache.")
                        throw CancellationError() 
                    }
                    
                    // Cache on main actor
                    await MainActor.run { 
                        self.promptResultCache = result 
                        Self.logger.debug("Prompt cache stored: \(result.chunks.count) chunks, \(result.combined.count) bytes")
                    }
                    
                    // Determine final state
                    finalState = criticalErrors.isEmpty ? 
                        .success("Prompt complete.") : 
                        .error("Prompt completed with \(criticalErrors.count) critical error(s).")

                case .pdf:
                    let result = await generatePDF(selectedItems: selectedItems)
                    
                    // Check cancellation *before* cache update
                    guard !isCancelled else { 
                        Self.logger.info("Processing cancelled before storing PDF cache.")
                        throw CancellationError() 
                    }
                    
                    // Cache on main actor
                    await MainActor.run {
                        self.pdfResultCache = result.pdf
                        self.skipInfoCache = result.skips
                        if let pdf = result.pdf {
                            Self.logger.debug("PDF cache stored: \(pdf.pageCount) pages, \(result.skips.count) skipped items")
                        } else {
                            Self.logger.warning("PDF generation produced no PDF document")
                        }
                    }
                    
                    // Determine final state
                    if criticalErrors.isEmpty {
                        if result.pdf == nil && !result.skips.isEmpty { 
                            finalState = .error("PDF generation skipped some files.") 
                        }
                        else if result.pdf == nil && result.skips.isEmpty { 
                            finalState = .error("No content for PDF.") 
                        }
                        else { 
                            finalState = .success("PDF complete.") 
                        }
                    } else {
                        finalState = .error("Completed with \(criticalErrors.count) critical error(s).")
                    }
                }

                // Final state update (if not cancelled)
                guard !isCancelled else { 
                    Self.logger.info("Processing cancelled before final state update.")
                    throw CancellationError() 
                }
                
                // Update final processing state
                await MainActor.run { processingState = finalState }
                Self.logger.info("Processing task finished. Final state: \(String(describing: finalState))")

            } catch is CancellationError {
                Self.logger.info("Processing task properly cancelled.")
                
                // Only reset state if cancellation was intentional
                if isCancelled {
                    await MainActor.run { 
                        clearAll(keepFiles: true) // Reset state while keeping files
                    }
                }
            } catch {
                Self.logger.error("Unexpected processing error: \(error.localizedDescription)")
                await MainActor.run {
                    criticalErrors.append("Unexpected processing error: \(error.localizedDescription)")
                    processingState = .error("Processing failed with error.")
                }
            }
            
            // Clear task reference on completion/cancellation
            await MainActor.run { processingTask = nil }
        }
    }

    func cancelProcessing() {
        if let task = processingTask, !task.isCancelled {
            Self.logger.info("Cancelling processing task.")
            // *** Set flag FIRST ***
            isCancelled = true
            processingState = .cancelling
            task.cancel()
            // Don't reset state here, let the cancelled task handle it via the catch block
        } else if processingState == .scanning("") || processingState == .preparing {
            // Handle cancelling scan/prepare phase
            Self.logger.info("Cancelling scanning/preparing phase.")
            isCancelled = true // Set flag
            processingState = .cancelling
            // Give a moment for async scan loop to check flag
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if self.processingState == .cancelling { // If still cancelling
                    self.clearAll(keepFiles: true) // Reset state but keep files
                    self.isCancelled = false // Reset flag
                }
            }
        }
    }

    // MARK: - Bookmark & Security Helpers (CRITICAL) -

    /// Attempts to secure access to a URL using stored bookmark data.
    /// Returns the scoped URL and a Bool indicating if access was started (needs stopping).
    private func secureAccess(for originalUrl: URL) async -> (URL, Bool)? {
         guard let bookmarkData = fileBookmarks[originalUrl] else {
             Self.logger.error("Access Error (\(originalUrl.lastPathComponent)): No bookmark data found. Path: \(originalUrl.path)")
             await MainActor.run { criticalErrors.append("Permission Error: Cannot find security info for \(originalUrl.lastPathComponent).") }
             return nil
         }
         Self.logger.debug("Found bookmark data for \(originalUrl.lastPathComponent)")
         return await secureAccess(bookmarkData: bookmarkData, originalUrlHint: originalUrl)
     }

    /// Low-level bookmark resolution and access start.
     private func secureAccess(bookmarkData: Data, originalUrlHint: URL? = nil) async -> (URL, Bool)? {
         let itemName = originalUrlHint?.lastPathComponent ?? "Unknown"
         Self.logger.debug("Securing access for \(itemName), bookmark size: \(bookmarkData.count) bytes")
         
         var isStale = false
         do {
             // Resolve the bookmark
              let scopedURL = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
              Self.logger.debug("Bookmark resolved for \(itemName): \(scopedURL.path)")

             if isStale {
                  Self.logger.warning("Bookmark is stale for \(itemName). Attempting to refresh.")
                  // Try to create a new bookmark from the resolved URL
                  if let newBookmarkData = try? scopedURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil),
                     let originalUrl = originalUrlHint { // Need original URL to update dictionary
                       await MainActor.run { fileBookmarks[originalUrl] = newBookmarkData } // Update stored bookmark
                      Self.logger.info("Successfully refreshed stale bookmark for \(itemName).")
                  } else {
                       Self.logger.error("Failed to refresh stale bookmark for \(itemName).")
                       // Proceed with stale access, but log it
                  }
             }

             // Start accessing the resource
             Self.logger.debug("Attempting to start secure access for \(itemName)")
             let accessStarted = scopedURL.startAccessingSecurityScopedResource()
             if !accessStarted {
                 Self.logger.error("Access Error (\(itemName)): Failed to start secure access after resolving bookmark. Path: \(scopedURL.path)")
                  await MainActor.run { criticalErrors.append("Permission Error: Cannot access \(itemName) after resolving.") }
                 return nil
             }
              Self.logger.debug("Successfully started secure access for \(itemName) at \(scopedURL.path)")
             return (scopedURL, true) // Return scoped URL and flag that access started

         } catch {
             Self.logger.error("Bookmark Error (\(itemName)): Failed to resolve bookmark: \(error.localizedDescription)")
             await MainActor.run { criticalErrors.append("Permission Error: Cannot resolve security info for \(itemName).") }
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

    // Helper to check cache existence
    private func cacheExists(for mode: Mode) -> Bool {
        switch mode {
        case .prompt: return promptResultCache != nil
        case .pdf: return pdfResultCache != nil
        }
    }
} 