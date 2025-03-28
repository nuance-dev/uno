// ContentView.swift
import SwiftUI
import UniformTypeIdentifiers
import PDFKit
import os // Keep Logger
import UserNotifications

private let logger = Logger(subsystem: "me.nuanc.Uno", category: "ContentView")

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @State private var isDragging = false
    @EnvironmentObject var updater: UpdateChecker

    var body: some View {
        ZStack(alignment: .bottom) { // Base ZStack
            // Animated switcher between Empty and Processing states
            Group {
                switch viewModel.viewState {
                case .empty:
                    EmptyStateView(isDragging: $isDragging) { openFilePicker() }
                        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                case .filesPresent:
                    ProcessingView(viewModel: viewModel)
                        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Apply a consistent, clean background
            .background(.background.secondary.opacity(0.1)) // Very subtle secondary background
            .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers, _ in
                handleDrop(providers)
                return true
            }
            .overlay(isDragging ? dropIndicatorOverlay : nil) // Use consistent drop overlay

            // Status Bar - always present but content changes
            StatusBar(viewModel: viewModel)
        }
        .frame(minWidth: 550, idealWidth: 750, minHeight: 450, idealHeight: 650)
        // Request notification permission on launch (needed for PDF save confirmation)
        .task {
             do {
                 let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                 logger.debug("Notification permission granted: \(granted)")
             } catch {
                 logger.error("Notification permission error: \(error.localizedDescription)")
             }
        }
    }

    // Consistent visual cue for dropping
    private var dropIndicatorOverlay: some View {
        Rectangle()
            .fill(Color.accentColor.opacity(0.1))
            .overlay(Rectangle().stroke(Color.accentColor.opacity(0.5), lineWidth: 2))
            .padding(4)
    }

    // MARK: - Actions & Helpers -
    private func handleDrop(_ providers: [NSItemProvider]) {
        // Capture providers immediately to minimize sendable issues
        let providersCopy = providers
        
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providersCopy {
                if let url = await loadURL(from: provider) {
                    urls.append(url)
                }
            }
            if !urls.isEmpty {
                viewModel.addUrls(urls)
            }
        }
    }
    
    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.begin { response in
            if response == .OK {
                viewModel.addUrls(panel.urls)
            }
        }
    }
    
    private func loadURL(from provider: NSItemProvider) async -> URL? {
        do {
            let item = try await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier)
            
            // Handle direct URL data (not bookmark)
            if let urlData = item as? Data,
               let urlString = String(data: urlData, encoding: .utf8)?.removingPercentEncoding,
               let url = URL(string: urlString) {
                logger.debug("Received direct URL: \(url.lastPathComponent)")
                return url
            }
            
            // Handle bookmark data (with proper error handling)
            if let bookmarkData = item as? Data {
                do {
                    var isStale = false
                    let url = try URL(resolvingBookmarkData: bookmarkData, 
                                      options: .withSecurityScope,
                                      relativeTo: nil, 
                                      bookmarkDataIsStale: &isStale)
                    
                    logger.debug("Resolved URL from bookmark: \(url.lastPathComponent), stale: \(isStale)")
                    // Don't start accessing now - let the ViewModel handle it properly
                    // The access start/stop needs to be tightly paired in processing
                    return url
                } catch {
                    logger.error("Invalid bookmark data: \(error.localizedDescription)")
                    // Continue to try other parsing methods - don't return nil yet
                }
            }
            
            // Last resort for NSURLs
            if let url = item as? URL {
                logger.debug("Received URL object directly: \(url.lastPathComponent)")
                return url
            }
            
            logger.warning("Could not parse drop item as URL: \(String(describing: item))")
            return nil
        } catch {
            logger.error("Error loading item: \(error.localizedDescription)")
            return nil
        }
    }
}

// MARK: - EmptyStateView

struct EmptyStateView: View {
    @Binding var isDragging: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(isDragging ? Color.accentColor : .secondary.opacity(0.6))
                .symbolEffect(.variableColor.iterative.reversing, options: .speed(0.8), isActive: isDragging)

            VStack(spacing: 4) {
                 Text("Drop Files or Folders Here")
                     .font(.system(size: 18, weight: .medium))
                     .foregroundColor(.primary.opacity(0.9))

                 Text("or click to select")
                     .font(.system(size: 13))
                     .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - ProcessingView

struct ProcessingView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showSettingsPopover: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Conditionally show controls based on fileTree, not viewState
            if !viewModel.fileTree.isEmpty {
                // Minimal Top Bar
                HStack {
                    modeSwitcher
                    Spacer()
                    fileInfoAndClear
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)

                Divider()
            }

            // Main Preview Area (occupies rest of space)
            previewArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped() // Prevent content overflow during transitions
        }
        .popover(isPresented: $showSettingsPopover, arrowEdge: .top) {
             SettingsPopover(viewModel: viewModel)
        }
    }

    // MARK: - Subviews -

    private var modeSwitcher: some View {
        Picker("Mode", selection: $viewModel.currentMode.animation()) {
            ForEach(AppViewModel.Mode.allCases) { mode in
                Label(mode.rawValue, systemImage: mode == .prompt ? "text.quote" : "doc.richtext")
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 130) // Compact switcher
    }

    private var fileInfoAndClear: some View {
        HStack(spacing: 12) {
             // File Count (Subtle)
             Text("\(viewModel.fileItemsList.count) file(s)")
                 .font(.callout)
                 .foregroundStyle(.secondary)

             // Settings Button
             Button { showSettingsPopover = true } label: {
                 Label("Settings", systemImage: "slider.horizontal.3")
             }
             .help("Configure Output")

             // Clear Button
             Button(role: .destructive) { viewModel.clearAll() } label: {
                 Label("Clear", systemImage: "xmark")
             }
             .help("Clear All Files")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .labelStyle(.iconOnly) // Icons only for minimal look
    }

    @ViewBuilder
    private var previewArea: some View {
        Group {
            if case .scanning = viewModel.processingState {
                ScanningView()
            } else if case .preparing = viewModel.processingState {
                PreparingView()
            } else if case .processing = viewModel.processingState {
                ZStack(alignment: .topTrailing) {
                    // Regular content
                    Group {
                        if viewModel.currentMode == .prompt {
                            PromptPreview(viewModel: viewModel)
                        } else {
                            PDFPreview(
                                pdfDocument: viewModel.generatedPDF,
                                isLoading: viewModel.processingState.isProcessing,
                                skippedFiles: viewModel.skippedFilesInfo,
                                viewModel: viewModel
                            )
                        }
                    }
                    
                    // Cancel button
                    Button {
                        viewModel.cancelProcessing()
                    } label: {
                        Label("Cancel", systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())
                    .help("Cancel current operation")
                }
            } else {
                // Not scanning and not processing - regular content
                if viewModel.currentMode == .prompt {
                    PromptPreview(viewModel: viewModel)
                } else {
                    PDFPreview(
                        pdfDocument: viewModel.generatedPDF,
                        isLoading: viewModel.processingState.isProcessing,
                        skippedFiles: viewModel.skippedFilesInfo,
                        viewModel: viewModel
                    )
                }
            }
        }
    }

    private var processingIndicator: some View {
        // Subtle centered spinner
        ProgressView()
            .controlSize(.small)
            .padding(12)
            .background(.ultraThinMaterial, in: Circle())
            .transition(.opacity.animation(.easeInOut))
    }
}

// MARK: - Preview Components

struct PromptPreview: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showCopiedMessage = false
    @State private var skippedFilesShown = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Preview Area
            ZStack(alignment: .center) {
                ScrollView {
                    if viewModel.promptChunks.isEmpty && !viewModel.processingState.isProcessing {
                        Text("Prompt preview will appear here.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            TextEditor(text: .constant(viewModel.promptChunks.joined()))
                                .font(.system(size: 12, design: .monospaced))
                                .scrollContentBackground(.hidden)
                                .padding(.horizontal, 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    }
                }
                .background(Color(.textBackgroundColor).opacity(0.4))
                
                // "Copied" Feedback
                if showCopiedMessage {
                    Text("Copied to Clipboard")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.accentColor)
                                .shadow(radius: 3)
                        )
                        .transition(.opacity.combined(with: .scale))
                }
            }
            
            if !viewModel.skippedFilesInfo.isEmpty && !skippedFilesShown {
                // Notification about skipped files
                Button {
                    skippedFilesShown = true
                } label: {
                    Text("\(viewModel.skippedFilesInfo.count) file(s) were skipped")
                        .font(.caption)
                    +
                    Text(" (click for details)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
                .background(.thinMaterial)
                .sheet(isPresented: $skippedFilesShown) {
                    SkippedFilesPopover(skippedFiles: viewModel.skippedFilesInfo)
                        .frame(minWidth: 300, minHeight: 200)
                        .padding()
                }
            }
            
            Divider()
            
            // Copy Button
            HStack {
                Spacer()
                Button {
                    copyPromptToClipboard()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .symbolEffect(.bounce, value: showCopiedMessage)
                }
                .keyboardShortcut("c", modifiers: [.command])
                .disabled(viewModel.promptChunks.isEmpty)
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func copyPromptToClipboard() {
        let combinedPrompt = viewModel.promptChunks.joined()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(combinedPrompt, forType: .string)
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
            showCopiedMessage = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showCopiedMessage = false
            }
        }
    }
}

struct PDFPreview: View {
    let pdfDocument: PDFDocument?
    let isLoading: Bool
    let skippedFiles: [AppViewModel.SkippedItemInfo]
    @ObservedObject var viewModel: AppViewModel
    
    @State private var zoomLevel: CGFloat = 1.0
    @State private var showSkippedFilesPopover = false
    @State private var showSaveErrorAlert = false
    @State private var saveErrorMessage = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            // PDF View
             Group {
                 if let pdf = pdfDocument {
                     EnhancedPDFKitView(pdfDocument: pdf, zoomLevel: $zoomLevel)
                 } else if !isLoading {
                     Text("PDF preview will appear here.")
                         .font(.callout)
                         .foregroundStyle(.secondary)
                         .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                 } else {
                     Color.clear // Placeholder during load
                 }
             }
             .frame(maxWidth: .infinity, maxHeight: .infinity)
             .background(Color(.textBackgroundColor).opacity(0.4))

            // Floating Control Bar at the Bottom
            if pdfDocument != nil {
                 pdfControls
                     .padding(.bottom, 10)
                     .padding(.horizontal)
                     .transition(.opacity.combined(with: .move(edge: .bottom)))
                     .animation(.spring(response: 0.4, dampingFraction: 0.8), value: pdfDocument)
             }
        }
        .alert("Error Saving PDF", isPresented: $showSaveErrorAlert) { 
            Button("OK") {} 
        } message: { 
            Text(saveErrorMessage) 
        }
        .popover(isPresented: $showSkippedFilesPopover, arrowEdge: .bottom) {
             SkippedFilesPopover(skippedFiles: skippedFiles)
        }
    }

    @ViewBuilder
    private var pdfControls: some View {
        HStack(spacing: 15) {
            // Skipped Files Button (if any)
            if !skippedFiles.isEmpty {
                Button { showSkippedFilesPopover = true } label: {
                    Label("\(skippedFiles.count) Skipped", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            Spacer()

            // Zoom Controls
            HStack(spacing: 5) {
                Button { zoomLevel = max(0.1, zoomLevel - 0.1) } label: { Image(systemName: "minus.magnifyingglass") }
                Button { zoomLevel = 1.0 } label: { Text("100%") }
                Button { zoomLevel = min(8.0, zoomLevel + 0.1) } label: { Image(systemName: "plus.magnifyingglass") }
            }
            .font(.callout)

            // Save Button
            Button { savePDF() } label: {
                Label("Save PDF", systemImage: "square.and.arrow.down")
            }
        }
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

    private func savePDF() {
        guard let pdfDoc = pdfDocument else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = "Uno-Merged-\(formattedTimestamp()).pdf"
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            Task {
                do {
                    let success = await Task.detached { pdfDoc.write(to: url) }.value
                    if success {
                        await MainActor.run {
                            sendSaveNotification(filePath: url.path)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                    } else {
                        throw NSError(domain: "SaveError", code: 1)
                    }
                } catch {
                    await MainActor.run {
                        saveErrorMessage = "Failed to save PDF: \(error.localizedDescription)"
                        showSaveErrorAlert = true
                    }
                }
            }
        }
    }
    
    private func formattedTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
    
    private func sendSaveNotification(filePath: String) {
        let content = UNMutableNotificationContent()
        content.title = "PDF Saved"
        content.body = "File saved: \(filePath.split(separator: "/").last ?? "")"
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

// MARK: - Supporting Components

struct SkippedFilesPopover: View {
    let skippedFiles: [AppViewModel.SkippedItemInfo]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Skipped Files")
                .font(.headline)
            
            Divider()
            
            if skippedFiles.isEmpty {
                Text("No files were skipped.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(skippedFiles) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 12, weight: .medium))
                                Text(item.reason)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .padding()
        .frame(width: 300)
    }
}

struct SettingsPopover: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Options")
                .font(.headline)
                .padding(.bottom, 5)

            if viewModel.currentMode == .prompt {
                Toggle("Include file tree structure", isOn: $viewModel.includeTreeInPrompt)
                    .onChange(of: viewModel.includeTreeInPrompt) { 
                        triggerReprocess()
                    }

                VStack(alignment: .leading, spacing: 3) {
                     Text("Max file size for full inclusion:")
                     HStack {
                         Slider(value: $viewModel.promptMaxSizeMB, in: 0.1...10.0, step: 0.1) {
                             Text("Max Size") // Accessibility label
                         }
                         .onChange(of: viewModel.promptMaxSizeMB) {
                             triggerReprocessDebounced()
                         }

                         Text("\(viewModel.promptMaxSizeMB, specifier: "%.1f") MB")
                             .font(.system(.body, design: .monospaced).weight(.medium))
                             .frame(width: 65, alignment: .trailing)
                     }
                 }
                 .controlSize(.small)

            } else {
                Text("No specific PDF options yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(minWidth: 280, idealWidth: 320)
    }

     private func triggerReprocess() {
          Task { await viewModel.triggerProcessing() }
     }

     private func triggerReprocessDebounced() {
         Task { await viewModel.triggerProcessing() }
     }
}

struct StatusBar: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showErrorPopover = false

    var body: some View {
        HStack(spacing: 8) {
            statusInfo
            Spacer()
            if !viewModel.criticalErrors.isEmpty {
                 errorButton
             }
        }
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .popover(isPresented: $showErrorPopover, arrowEdge: .bottom) {
             CriticalErrorsPopover(errors: viewModel.criticalErrors)
        }
    }

    @ViewBuilder
    private var statusInfo: some View {
        Group {
             switch viewModel.processingState {
             case .idle:
                 if viewModel.viewState == .empty {
                     Text("Add Files or Folders")
                 } else {
                      Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green.opacity(0.7))
                      Text("Ready")
                 }
             case .scanning(let folderName):
                 ProgressView().controlSize(.small).padding(.trailing, 4)
                 Text("Scanning \(folderName)...")
             case .preparing:
                 ProgressView().controlSize(.small).padding(.trailing, 4)
                 Text("Preparing...")
             case .processing(let progress, let step):
                 ProgressView(value: progress).controlSize(.small).frame(width: 60).padding(.trailing, 4)
                 Text("\(progress * 100, specifier: "%.0f")% - \(step)").monospacedDigit()
             case .cancelling:
                 ProgressView().controlSize(.small).padding(.trailing, 4)
                 Text("Cancelling...").foregroundStyle(.orange)
             case .error(let message):
                  Label(message, systemImage: "exclamationmark.triangle")
                     .foregroundStyle(.red)
                     .onTapGesture { showErrorPopover = true }
             case .success(let message):
                 Label(message, systemImage: "checkmark.circle.fill")
                     .foregroundStyle(.green)
             }
        }
        .foregroundStyle(.secondary)
    }

     private var errorButton: some View {
         Button {
             showErrorPopover = true
         } label: {
             Label("\(viewModel.criticalErrors.count) Critical Error(s)", systemImage: "exclamationmark.circle.fill")
                 .labelStyle(.iconOnly)
                 .foregroundStyle(.red)
         }
         .buttonStyle(.plain)
         .help("Show critical errors")
     }
}

struct CriticalErrorsPopover: View {
    let errors: [String]
    var body: some View {
         VStack(alignment: .leading) {
             Text("Critical Errors").font(.headline)
             Divider()
             ScrollView { 
                ForEach(errors, id: \.self) { error in
                    Text(error).font(.caption)
                }
             }
             .frame(maxHeight: 150)
         }
         .padding()
         .frame(minWidth: 250, idealWidth: 300)
     }
}

// MARK: - PDF Kit Component

struct ScanningView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .scaleEffect(1.5)
            
            Text("Scanning Files...")
                .font(.headline)
            
            Text("Building file hierarchy")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PreparingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .scaleEffect(1.5)
            
            Text("Preparing...")
                .font(.headline)
            
            Text("Setting up processor")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
} 