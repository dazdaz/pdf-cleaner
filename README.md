# PDF Cleaner

A shell-based workflow that removes specific text from a PDF, regenerates the document with Puppeteer for high-fidelity output, and applies file-size optimizations using PDF Squeezer by default with Ghostscript as a fallback.

> **Platform:** This script is built for macOS (Darwin) systems and will refuse to run on other operating systems.

## Features

- Converts PDFs to HTML using `pdf2htmlEX`, removes target strings via `sed`, and rebuilds the PDF with a custom Puppeteer script.
- Uses the PDF Squeezer helper binary (`/Applications/PDF Squeezer.app/Contents/Helpers/pdfs`) with medium compression for optimal macOS results.
- Falls back to Ghostscript compression when the helper is unavailable or fails.
- Creates per-run working directories (`./pdfclean-XXXXXX`) for easy inspection, with optional preservation via `--keep-temp`.
- Captures verbose logs for PDF Squeezer and enforces a configurable timeout to prevent hangs.

## Requirements

All installation commands and runtime dependencies assume macOS with Homebrew available.

### Core dependencies

1. **pdf2htmlEX** (conversion to HTML)  
   ```bash
   brew install pdf2htmlEX
   ```

2. **Node.js** and **npm**  
   Install from [https://nodejs.org](https://nodejs.org). The script expects Puppeteer to be available:
   ```bash
   npm install -g puppeteer
   ```

### Preferred compression (macOS)

- **PDF Squeezer** – install via the Mac App Store or from [https://witt-software.com/squeezer](https://witt-software.com/squeezer).  
  The script invokes the bundled helper located at:  
  `/Applications/PDF Squeezer.app/Contents/Helpers/pdfs`

Optional environment variables:

- `PDFSQUEEZER_TIMEOUT` (default `120`) – seconds to wait before terminating the helper.
- `PDFSQUEEZER_EXTRA_ARGS` – additional CLI flags appended to the helper call.

### Fallback compression

- **Ghostscript** – only required if you want the fallback to run.  
  ```bash
  brew install ghostscript
  ```

If neither PDF Squeezer nor Ghostscript is present, the script still produces an output PDF without additional compression.

## Usage

This workflow runs exclusively on macOS (Darwin).

```bash
./pdf-cleaner.sh input.pdf output.pdf 'text to remove' [--keep-temp]
```

- `input.pdf` – source document.
- `output.pdf` – destination path.
- `'text to remove'` – exact string (quote if it contains spaces or punctuation).
- `--keep-temp` – optional flag to retain the working directory for debugging.

Example:

```bash
PDFSQUEEZER_TIMEOUT=180 ./pdf-cleaner.sh \
  book.pdf \
  book-clean.pdf \
  'Randomtext: blahblah' \
  --keep-temp
```

## What to expect

1. `pdf2htmlEX` writes HTML assets into the local temp folder.  
2. `sed` removes the requested string.  
3. `html-to-pdf.js` (Puppeteer) regenerates the PDF.  
4. PDF Squeezer helper attempts medium compression.  
5. If PDF Squeezer fails or times out, Ghostscript runs (when installed).  
6. The smallest successful artifact is copied to `output.pdf`.

## Logs and troubleshooting

- PDF Squeezer logs: `<tempdir>/pdfsqueezer.log`
- If the helper hangs or exits unsuccessfully, the script warns you and points to the log file.
- To inspect intermediate HTML/PDF artifacts, pass `--keep-temp`.
- Adjust Ghostscript quality by editing the `-dPDFSETTINGS` value inside the script if the fallback is used.

Common issues:

- **Command not found** – ensure every dependency above is in your `PATH`.
- **Permission denied** – mark the script executable: `chmod +x pdf-cleaner.sh`.
- **Fonts or images missing** – verify fonts are installed locally; consider tweaking Puppeteer viewport or wait logic in `html-to-pdf.js`.

## Development

1. Clone the repo:
   ```bash
   git clone https://github.com/dazdaz/pdf-cleaner.git
   cd pdf-cleaner
   ```
2. Install prerequisites (see above).
3. Run the script against a sample file and review the output plus logs.
4. Submit pull requests with descriptive commit messages.

## License

This project is open source. Only process documents you are legally permitted to modify.
