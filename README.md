# Uno - A macOS file merger to prompt or PDF

A sleek, native macOS app that transforms files into unified prompts or merges them into PDFs. Perfect for preparing training data or combining documents.

Note: This app requires macOS version 14+

![uno-banner](https://github.com/user-attachments/assets/d0c81519-82bc-4554-a528-10b2e54cec1c)

## Features

- **Prompt Mode**: Convert files into a single, structured prompt
  - Supports multiple file types (.pdf, .swift, .ts, .js, .html, .css, etc.)
  - Maintains file structure in output
  - Folder support for batch processing
- **PDF Mode**: Merge multiple files into a single PDF
  - Smart conversion of non-PDF files
  - Maintains document order
  - Preview support
- **Syntax Highlighting**: Automatic language detection and code highlighting
- **File Tree**: Include file structure in prompts for better context
- **Multiple Output Formats**: Standard, File Tree, or Markdown formatting
- **PDF Generation**: Create professional PDFs with title pages, table of contents, and proper formatting

**Pro tip:** Throw a folder and it will convert it all


https://github.com/user-attachments/assets/e9d0838a-e99d-42a7-aed3-a217d56831ed


## 💻 Get it

Download from the [releases](https://github.com/nuance-dev/Uno/releases/) page.

## 🔒 Security

- Each piece is individually encrypted using AES-GCM encryption
- Unique salt and key derivation for each piece
- Original file can only be recovered with all 3 pieces
- Two modes available:
  - **Standard Mode**: Basic file splitting with LZFSE compression
  - **Secure Mode**: Adds military-grade encryption to each piece
- Perfect for distributing sensitive files across different channels

## 🤝 Contributing

We welcome contributions! Here's how you can help:

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

Please ensure your PR:

- Follows the existing code style
- Includes appropriate tests
- Updates documentation as needed

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links

- Website: [Nuanc.me](https://nuanc.me)
- Report issues: [GitHub Issues](https://github.com/nuance-dev/Uno/issues)
- Follow updates: [@Nuanced](https://twitter.com/Nuancedev)

## Installation

### Prerequisites

- macOS 12.0 or later
- Xcode 13.0 or later

### Setup

1. Clone this repository
2. Open the Xcode project
3. Add the Highlightr dependency:
   - In Xcode, go to File > Add Packages...
   - Paste the URL: `https://github.com/raspu/Highlightr.git`
   - Click "Add Package"
4. Build and run the application

## Usage

1. **Drop Files**: Drag and drop files or folders onto the application
2. **Choose Mode**: Select "Prompt" or "PDF" mode
3. **Configure Options**: 
   - Enable/disable syntax highlighting
   - Choose prompt format style
   - Include file tree structure
4. **Export**: Copy prompt content or save PDF to your desired location

## Supported File Types

Uno supports a wide range of file types including:

- Code files (Swift, JavaScript, Python, HTML, CSS, etc.)
- Documentation (Markdown, Text, PDF)
- Data files (JSON, YAML, XML, CSV)
- Configuration files (INI, ENV, etc.)
- Images (JPG, PNG, etc.) for PDF mode

## Development

The application uses SwiftUI and leverages several native frameworks:

- SwiftUI for the user interface
- PDFKit for PDF generation and manipulation
- Highlightr for syntax highlighting
