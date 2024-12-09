import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var manager = FileHandlerManager()
    @State private var isDragging = false
    @State private var mode = Mode.breakFile
    
    enum Mode: Hashable {
        case breakFile
        case mend
    }
    
    var body: some View {
        ZStack {
            VisualEffectBlur(material: .headerView, blendingMode: .behindWindow)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Modern Tab Switcher with Secure Mode
                HStack(spacing: 16) {
                    // Tab switcher
                    HStack(spacing: 0) {
                        ForEach([Mode.breakFile, Mode.mend], id: \.self) { tabMode in
                            Button(action: { 
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    mode = tabMode
                                }
                            }) {
                                Text(tabMode == .breakFile ? "Break" : "Mend")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(mode == tabMode ? 
                                        Color(NSColor.controlAccentColor) : 
                                        Color.secondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(mode == tabMode ? 
                                                Color(NSColor.controlAccentColor).opacity(0.1) : 
                                                Color.clear)
                                    )
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            .frame(width: 120)
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(NSColor.windowBackgroundColor).opacity(0.5))
                            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    
                    if mode == .breakFile {
                        // Secure Mode Toggle
                        Button {
                            manager.isSecureMode.toggle()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: manager.isSecureMode ? "lock.fill" : "lock.open.fill")
                                    .foregroundStyle(manager.isSecureMode ? Color.accentColor : .secondary)
                                    .font(.system(size: 13, weight: .medium))
                                    .contentTransition(.symbolEffect(.replace))
                                
                                Text("Secure")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(manager.isSecureMode ? Color.primary : .secondary)
                            }
                            .frame(height: 36)
                            .padding(.horizontal, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(manager.isSecureMode ? 
                                        Color.accentColor.opacity(0.1) : 
                                        Color(NSColor.windowBackgroundColor).opacity(0.5))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(manager.isSecureMode ? 
                                        Color.accentColor.opacity(0.2) : 
                                        Color.primary.opacity(0.08),
                                        lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .help("Enables military-grade encryption (AES-GCM) with unique keys for each piece")
                    }
                }
                .padding(.horizontal)
                
                ZStack {
                    if mode == .breakFile {
                        if manager.pieces.isEmpty {
                            DropZoneView(isDragging: $isDragging) {
                                handleFileSelection()
                            }
                        } else {
                            // Improved file list view
                            VStack(spacing: 16) {
                                HStack {
                                    Text("File Pieces")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(manager.pieces.count)/3")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(6)
                                }
                                
                                ForEach(manager.pieces, id: \.self) { url in
                                    HStack(spacing: 12) {
                                        Image(systemName: "doc.fill")
                                            .foregroundColor(.accentColor)
                                            .font(.system(size: 20))
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(url.lastPathComponent)
                                                .font(.system(.body, design: .monospaced))
                                                .lineLimit(1)
                                            
                                            Text(formatFileSize(url))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            NSWorkspace.shared.selectFile(url.path, 
                                                                inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                                        }) {
                                            Image(systemName: "folder")
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        .help("Show in Finder")
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color(NSColor.windowBackgroundColor).opacity(0.5))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                                    )
                                }
                            }
                            .padding(.horizontal)
                        }
                    } else {
                        DropZoneView(isDragging: $isDragging) {
                            handlePieceSelection()
                        }
                    }
                    
                    if manager.isLoading {
                        LoaderView()
                    }
                    
                    if case .error(let message) = manager.uploadState {
                        Text(message)
                            .foregroundColor(.red)
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)
                    }
                }
                
                if !manager.pieces.isEmpty && mode == .breakFile {
                    ButtonGroup(buttons: [
                        (
                            title: "Save All",
                            icon: "arrow.down.circle",
                            action: savePieces
                        ),
                        (
                            title: "Clear",
                            icon: "trash",
                            action: manager.clearFiles
                        )
                    ])
                    .disabled(manager.isLoading)
                }
            }
            .padding(30)
        }
        .frame(minWidth: 600, minHeight: 700)
        .onDrop(of: [UTType.item], isTargeted: $isDragging) { providers in
            loadDroppedFiles(providers)
            return true
        }
    }
    
    private func handleFileSelection() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.item]
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                manager.handleFileSelection(url)
            }
        }
    }
    
    private func handlePieceSelection() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.item]
        
        panel.begin { response in
            if response == .OK, panel.urls.count == 3 {
                manager.mendFiles(panel.urls)
            } else {
                manager.uploadState = .error("Please select exactly 3 pieces")
            }
        }
    }
    
    private func loadDroppedFiles(_ providers: [NSItemProvider]) {
        if mode == .breakFile {
            guard let provider = providers.first else { return }
            provider.loadItem(forTypeIdentifier: UTType.item.identifier, options: nil) { item, error in
                if let url = item as? URL {
                    DispatchQueue.main.async {
                        self.manager.handleFileSelection(url)
                    }
                }
            }
        } else {
            // Handle mending mode
            let group = DispatchGroup()
            var urls: [URL] = []
            
            providers.forEach { provider in
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.item.identifier, options: nil) { item, error in
                    defer { group.leave() }
                    if let url = item as? URL {
                        urls.append(url)
                    }
                }
            }
            
            group.notify(queue: .main) {
                if urls.count == 3 {
                    self.manager.mendFiles(urls)
                } else {
                    self.manager.uploadState = .error("Please drop exactly 3 file pieces")
                }
            }
        }
    }
    
    private func savePieces() {
        manager.saveAllPieces()
    }
    
    private func formatFileSize(_ url: URL) -> String {
        do {
            let resources = try url.resourceValues(forKeys: [.fileSizeKey])
            if let size = resources.fileSize {
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
                formatter.countStyle = .file
                return formatter.string(fromByteCount: Int64(size))
            }
        } catch {
            print("Error getting file size: \(error)")
        }
        return ""
    }
}
