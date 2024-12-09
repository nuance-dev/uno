# Uno - A macOS Native File Splitter & Joiner

A sleek, free native macOS app that splits files into three encrypted pieces and lets you join them back together. Perfect for securely sharing sensitive files across different channels.

Note: This app requires macOS version 14+

![uno-banner](https://github.com/user-attachments/assets/117759b7-ebd0-4b04-b8bf-482169ea55ff)

## Features

- **Split Files**: Break any file into 3 encrypted pieces
- **Join Files**: Easily combine the pieces back into the original file
- **Multiple Input Methods**: Drag & drop, paste (⌘V), or click to upload
- **Native Performance**: Built with SwiftUI for optimal processing
- **Dark and Light modes**: Automatically matches your system theme

https://github.com/user-attachments/assets/ea628ef4-4e09-498a-ad5c-2a093028c669

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

### How Secure Mode Works

- Each piece is independently encrypted using AES-GCM
- Keys are derived using HKDF with SHA-256
- Unique salt generated for each piece
- Key material is derived from the original file's hash
- Without all three pieces and the original file hash, decryption is computationally infeasible

## 🥑 Fun facts

- Yes this app can be used to host the best treasure hunt of all time

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
