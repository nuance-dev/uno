# Uno - A macOS file merger to PDF and prompt

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

**Pro tip:** Throw a folder and it will convert it all

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
