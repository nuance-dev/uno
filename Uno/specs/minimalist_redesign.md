# Uno Minimalist Redesign

## Core Principles

- **Minimalism, Elegance, and Intelligence**: Inspired by Raycast, Linear, Vercel, Craft
- **Default State Simplicity**: Clean, focused solely on adding files (drop zone)
- **Contextual UI**: Elements appear only when needed
- **Fluid Transitions**: Smooth, non-jarring state changes with animations
- **Integrated Preview**: The preview area becomes the main content area
- **Smart Error Handling**: Non-critical errors embedded directly in output, critical errors minimally summarized
- **Streamlined Configuration**: Settings tucked away, contextually accessible
- **Modern Aesthetics**: Materials, SF Symbols, subtle shadows, rounded corners

## Architecture

### View Structure

- **`ContentView`**: Manages top-level state (`empty` vs. `filesPresent`) and transitions
- **`EmptyStateView`**: Initial beautiful drop zone
- **`ProcessingView`**: Main view when files are loaded
  - Minimal top bar (mode switcher, file count/clear)
  - Primary preview area (switching between `PromptPreview` and `PDFPreview`)
  - Contextual controls (settings, copy/save)
- **`PromptPreview`**: Clean, scrollable text view with inline skip/error notes
- **`PDFPreview`**: `EnhancedPDFKitView` with floating controls
- **`SettingsPopover`**: Small popover for essential settings
- **`StatusBar`**: Minimal persistent status/error feedback

### ViewModel

- **`AppViewModel`** (Enhanced):
  - Refined state management (`ViewState`, `ProcessingState`)
  - Improved error/skip handling (inline prompt notes)
  - State preservation across mode changes
  - Dedicated PDF skip list generation

## User Experience Flow

1. **Empty State**: User sees a clean drop zone
2. **Add Files**: User drops files or selects them via click
3. **Processing**: Minimal loading indicator during processing
4. **Results View**: Based on selected mode:
   - **Prompt Mode**: Clean text display with inline error notes, copy button
   - **PDF Mode**: PDF preview with floating zoom/save controls, skipped files info

## Design Elements

- **Materials**: `.ultraThinMaterial`, `.regularMaterial` for UI components
- **Controls**: Minimal, visible only when needed
- **Transitions**: Smooth `.opacity`, `.move` transitions
- **Feedback**: Contextual, non-intrusive error handling
- **Typography**: Clean, consistent font choices

## Implementation Details

- **Mode Switching**: Preserve file tree state across mode changes
- **Error Handling**: Embed non-critical errors directly in prompt text
- **PDF Skip List**: Show skipped files in a popover for PDF mode
- **Settings**: Minimal, contextual settings in a popover

## State Management

- **`ViewState`**: `empty` or `filesPresent`
- **`ProcessingState`**: `idle`, `scanning`, `processing`, `error`, `success`
- **Files**: `fileTree` maintains selected files consistently 