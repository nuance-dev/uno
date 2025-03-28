# Uno - macOS File Merger

A sleek, native macOS app that transforms files into unified prompts or merges them into PDFs. Perfect for consolidating information, preparing text for AI models, or combining documents.

Requires macOS 14+ (Ventura or later recommended for optimal SwiftUI features).

![uno-banner](https://github.com/user-attachments/assets/d0c81519-82bc-4554-a528-10b2e54cec1c)

## Features

-   **Two Modes:**
    -   **Prompt Mode**: Concatenates the content of selected files into a single text block, wrapping each file's content with tags indicating the filename (e.g., `<filename.txt>...</filename.txt>`). Ideal for preparing input for LLMs.
    -   **PDF Mode**: Merges multiple files into a single PDF document.
-   **File Support:**
    -   **Prompt Mode**: Supports a wide range of plain text files (code, markdown, `.txt`, config files, etc. based on UTTypes and common extensions) and extracts text content from PDFs.
    -   **PDF Mode**: Merges existing PDFs. Converts common image files (JPG, PNG, HEIC, TIFF, GIF, WebP, BMP, ICNS, RAW) and supported plain text files into pages within the final PDF. *Note: Direct conversion of complex formats like Office documents (.docx, .xlsx) is **not** currently supported.*
-   **Drag & Drop:** Easily add files or folders by dragging them onto the app window.
-   **Folder Processing:** Automatically finds and processes supported files within dropped folders (respecting `.gitignore`-like hidden files).
-   **Clean UI:** Native macOS look and feel with light and dark mode support, utilizing standard controls and materials.
-   **Preview:** View the generated prompt or PDF (with zoom) directly within the app.
-   **Export:** Copy the generated prompt to the clipboard or save the merged PDF with progress indication and notifications.
-   **Error Handling:** Displays specific errors encountered during file processing (e.g., unsupported types, access issues, large files).
-   **Auto-Update Check:** Checks for new versions on GitHub releases periodically and manually.

**Pro tip:** Drop a folder, and Uno will process all supported files inside it according to the selected mode.

[Link to GIF demonstrating folder drop]
https://github.com/user-attachments/assets/e9d0838a-e99d-42a7-aed3-a217d56831ed

## 💻 Get it

Download the latest version from the [Releases](https://github.com/nuance-dev/Uno/releases/) page.

## 🤝 Contributing

We welcome contributions! Here's how you can help:

1.  Fork the repository
2.  Create your feature branch (`git checkout -b feature/AmazingFeature`)
3.  Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4.  Push to the branch (`git push origin feature/AmazingFeature`)
5.  Open a Pull Request

Please ensure your PR:

-   Follows the existing code style
-   Includes appropriate tests (if applicable)
-   Updates documentation as needed

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔗 Links

-   Website: [Nuanc.me](https://nuanc.me)
-   Report issues: [GitHub Issues](https://github.com/nuance-dev/Uno/issues)
-   Follow updates: [@Nuancedev](https://twitter.com/Nuancedev) [Corrected Twitter handle]
