# Uno App Architecture

## Overview

Uno is a modern macOS application for processing files to generate AI prompts or PDF compilations. This document outlines the technical architecture and design decisions for the next-gen version of the app.

## Core Architecture

The application follows the MVVM (Model-View-ViewModel) architectural pattern:

- **Models**: Data structures representing files, folders, and their properties
- **ViewModels**: Manages state, business logic, and data transformations
- **Views**: UI components that present data and handle user interactions

## Key Components

### Models

- `FileItem`: Represents a file or folder in the hierarchical tree structure
  - Provides properties for file metadata (name, type, size)
  - Supports hierarchical relationships (parent-child)
  - Maintains selection state for processing inclusion

### ViewModel

- `AppViewModel`: Central state management and processing logic
  - Handles file system operations (scanning directories, reading files)
  - Processes files to generate prompts or PDFs
  - Manages processing state and error handling
  - Provides asynchronous operations using Swift Concurrency (async/await)

### Views

- **Left Pane (FileTreeView)**: Hierarchical tree view of files/folders
  - Uses `OutlineGroup` for expandable/collapsible tree display
  - Supports file selection/deselection
  - Shows file type icons and size information

- **Right Pane (RightPaneView)**: Content and settings based on mode
  - Prompt Mode: Configurable options, text preview, copy functionality
  - PDF Mode: PDF preview with zoom controls, save functionality
  - Error display and status reporting

- **Status Bar**: Processing status and progress reporting

## Modern Implementation Details

1. **Asynchronous Operations**:
   - All file I/O and processing happens off the main thread
   - Uses Swift Concurrency (Task, async/await) for clean asynchronous code
   - Provides progress and status updates during processing

2. **Dynamic File Handling**:
   - Uses UniformTypeIdentifiers (UTType) for file type detection
   - Handles various text encodings with fallback mechanisms
   - Size-based threshold for inclusion in prompts (configurable)

3. **Security**:
   - Sandbox-compatible file access
   - Security-scoped bookmarks for persistent file access
   - Proper resource cleanup

4. **UI Design**:
   - Modern macOS styling with materials and design patterns
   - Split view layout with resizable panes
   - Contextual feedback and error reporting
   - Responsive loading states
   - Direct manipulation of file selection in the tree

## Feature Implementation

### Prompt Generation
- Supports configurable size threshold for full inclusion
- Optional ASCII tree representation of file structure
- Properly formats file content with name tags
- Handles text encoding detection and conversion

### PDF Compilation
- Combines multiple file types into a single PDF
- Handles images, PDFs, and text files
- Maintains document structure and readability
- Supports zoom and navigation controls

## Technological Stack

- **SwiftUI**: Modern declarative UI framework
- **PDFKit**: Native PDF handling
- **UniformTypeIdentifiers**: Modern file type identification
- **Swift Concurrency**: Async programming model
- **Combine**: Reactive programming for UI updates (via ObservableObject) 