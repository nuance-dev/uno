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
            if let bookmarkData = item as? Data {
                var isStale = false
                if let scopedURL = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                    _ = scopedURL.startAccessingSecurityScopedResource() // Start access! Be careful.
                    return scopedURL
                }
            }
            if let urlData = item as? Data,
               let urlString = String(data: urlData, encoding: .utf8)?.removingPercentEncoding,
               let url = URL(string: urlString) {
                return url
            }
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
        ZStack {
            // Actual Preview Content
            Group {
                if viewModel.currentMode == .prompt {
                     PromptPreview(
                        content: viewModel.generatedPrompt,
                        isLoading: viewModel.processingState.isProcessing
                     )
                 } else {
                     PDFPreview(
                        pdfDocument: viewModel.generatedPDF,
                        isLoading: viewModel.processingState.isProcessing,
                        skippedFiles: viewModel.skippedFilesInfo,
                        viewModel: viewModel
                     )
                 }
            }
            .transition(.opacity.animation(.easeInOut))


            // Processing Indicator (Centered Overlay)
            if viewModel.processingState.isProcessing {
                processingIndicator
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
    let content: String
    let isLoading: Bool
    @State private var isCopied: Bool = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Use TextEditor directly for scrollable, selectable text
            TextEditor(text: .constant(content))
                .font(.system(size: 13, design: .monospaced))
                .padding(EdgeInsets(top: 10, leading: 15, bottom: 10, trailing: 45))
                .background(.clear)
                .foregroundStyle(.primary)
                .scrollContentBackground(.hidden)
                .opacity(content.isEmpty && !isLoading ? 0 : 1)


            // Placeholder when empty
             if content.isEmpty && !isLoading {
                 Text("Prompt will appear here.")
                     .font(.callout)
                     .foregroundStyle(.secondary)
                     .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
             }


            // Minimal Copy Button
            Button { copyToClipboard() } label: {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.plain)
            .foregroundStyle(isCopied ? .green : .secondary)
            .padding(12)
            .opacity(content.isEmpty ? 0 : 1)
            .animation(.easeInOut, value: isCopied)
            .disabled(content.isEmpty)
        }
    }

     private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        isCopied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { isCopied = false }
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
          Task { await viewModel.processFiles() }
     }

     private func triggerReprocessDebounced() {
         Task { await viewModel.processFiles() }
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
                 }
             case .scanning(let folderName):
                 ProgressView().controlSize(.small).padding(.trailing, 4)
                 Text("Scanning \(folderName)...")
             case .processing(let progress, _):
                 ProgressView(value: progress).controlSize(.small).frame(width: 60).padding(.trailing, 4)
                 Text("\(progress * 100, specifier: "%.0f")%").monospacedDigit()
             case .error(_):
                  Label("Error", systemImage: "exclamationmark.triangle")
                     .foregroundStyle(.red)
                     .onTapGesture { showErrorPopover = true }
             case .success(_):
                 Label("Complete", systemImage: "checkmark.circle.fill")
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
struct EnhancedPDFKitView: NSViewRepresentable {
    let pdfDocument: PDFDocument
    @Binding var zoomLevel: CGFloat
    
    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.document = pdfDocument
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .clear
        return pdfView
    }
    
    func updateNSView(_ pdfView: PDFView, context: Context) {
        pdfView.document = pdfDocument
        pdfView.scaleFactor = zoomLevel
    }
} 