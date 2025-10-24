#!/bin/bash

set -euo pipefail

if [ $# -lt 3 ] || [ $# -gt 4 ]; then
    echo "Usage: $0 input.pdf output.pdf 'text to remove' [--keep-temp]"
    exit 1
fi

input="$1"
output="$2"
text="$3"

KEEP_TEMP=false
if [ $# -eq 4 ]; then
    if [ "$4" = "--keep-temp" ]; then
        KEEP_TEMP=true
    else
        echo "Unknown option: $4"
        echo "Usage: $0 input.pdf output.pdf 'text to remove' [--keep-temp]"
        exit 1
    fi
fi

if [ ! -f "$input" ]; then
    echo "Input PDF not found: $input"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HTML_TO_PDF="$SCRIPT_DIR/html-to-pdf.js"

if [ ! -f "$HTML_TO_PDF" ]; then
    echo "html-to-pdf.js not found in $SCRIPT_DIR"
    exit 1
fi

if ! command -v pdf2htmlEX &> /dev/null; then
    echo "pdf2htmlEX is not installed. Install it using Homebrew: brew install pdf2htmlEX"
    exit 1
fi

if ! command -v node &> /dev/null; then
    echo "Node.js is not installed. Install it from https://nodejs.org/"
    exit 1
fi

if ! node -e "require('puppeteer')" &> /dev/null; then
    echo "Node.js module 'puppeteer' is not installed. Install it with: npm install puppeteer"
    exit 1
fi

HAS_PDFSQUEEZER=false
HAS_GS=false

PDFSQUEEZER_HELPER="/Applications/PDF Squeezer.app/Contents/Helpers/pdfs"
if [ -x "$PDFSQUEEZER_HELPER" ]; then
    HAS_PDFSQUEEZER=true
    echo "PDF Squeezer helper detected at $PDFSQUEEZER_HELPER"
else
    echo "PDF Squeezer helper CLI not found at $PDFSQUEEZER_HELPER"
fi

if command -v gs &> /dev/null && gs -h | grep -q pdfwrite; then
    HAS_GS=true
    echo "Ghostscript available for compression"
else
    echo "Ghostscript not found or missing pdfwrite device. Install with: brew install ghostscript"
fi

if [ "$HAS_PDFSQUEEZER" = false ] && [ "$HAS_GS" = false ]; then
    echo "No compression tools detected; output will remain uncompressed."
fi

tmpdir=$(mktemp -d "./pdfclean-XXXXXX" 2>/dev/null || mktemp -d -t pdfclean)
cleanup() {
    if [ "$KEEP_TEMP" = true ]; then
        echo "Skipping cleanup; temporary files preserved at $tmpdir"
        return
    fi
    rm -rf "$tmpdir"
}
trap cleanup EXIT

temp_html="$tmpdir/source.html"
modified_html="$tmpdir/modified.html"
temp_pdf="$tmpdir/clean.pdf"
pdfsqueezer_pdf="$tmpdir/pdfsqueezer.pdf"
pdfsqueezer_log="$tmpdir/pdfsqueezer.log"
gs_pdf="$tmpdir/gs.pdf"
PDFSQUEEZER_TIMEOUT=${PDFSQUEEZER_TIMEOUT:-120}

get_size() {
    local file="$1"
    local size
    if size=$(stat -f%z "$file" 2>/dev/null); then
        printf "%s" "$size"
    elif size=$(stat -c%s "$file" 2>/dev/null); then
        printf "%s" "$size"
    else
        size=$(wc -c < "$file")
        printf "%s" "$size"
    fi
}

format_size() {
    local size="$1"
    if command -v awk &> /dev/null; then
        local mb
        mb=$(awk -v size="$size" 'BEGIN { printf "%.2f", size/1048576 }')
        printf "%s bytes (%s MB)" "$size" "$mb"
    else
        printf "%s bytes" "$size"
    fi
}

echo "Converting PDF to HTML using pdf2htmlEX..."
pdf2htmlEX --dest-dir "$tmpdir" "$input" "$(basename "$temp_html")" > /dev/null

echo "Removing text from HTML..."
escaped_text=$(printf '%s' "$text" | sed -e 's/[\\/&]/\\&/g' -e 's/|/\\|/g')
sed "s|$escaped_text||g" "$temp_html" > "$modified_html"

echo "Converting modified HTML back to PDF using Puppeteer..."
node "$HTML_TO_PDF" "$modified_html" "$temp_pdf"

if [ ! -f "$temp_pdf" ]; then
    echo "Failed to generate cleaned PDF"
    exit 1
fi

mkdir -p "$(dirname "$output")"

echo "Evaluating compression options..."
best_pdf="$temp_pdf"
best_label="Original Puppeteer PDF"
best_size=$(get_size "$best_pdf")
echo " • Original size: $(format_size "$best_size")"

if [ "$HAS_PDFSQUEEZER" = true ]; then
    echo "Trying PDF Squeezer helper compression..."
    rm -f "$pdfsqueezer_pdf" "$pdfsqueezer_log"

    PDFSQUEEZER_ARGS=("$temp_pdf" "--output" "$pdfsqueezer_pdf" "--compression" "medium")
    if [ -n "${PDFSQUEEZER_EXTRA_ARGS:-}" ]; then
        # shellcheck disable=SC2206
        EXTRA_ARGS=($PDFSQUEEZER_EXTRA_ARGS)
        PDFSQUEEZER_ARGS+=("${EXTRA_ARGS[@]}")
    fi

    printf ' • Command: %q' "$PDFSQUEEZER_HELPER" >"$pdfsqueezer_log"
    for arg in "${PDFSQUEEZER_ARGS[@]}"; do
        printf ' %q' "$arg" >>"$pdfsqueezer_log"
    done
    printf '\n' >>"$pdfsqueezer_log"
    echo " • Command: $PDFSQUEEZER_HELPER ${PDFSQUEEZER_ARGS[*]}"
    echo " • Log file: $pdfsqueezer_log"

    ( "$PDFSQUEEZER_HELPER" "${PDFSQUEEZER_ARGS[@]}" >>"$pdfsqueezer_log" 2>&1 ) &
    pdfsqueezer_pid=$!
    pdfsqueezer_status=0
    elapsed=0
    while kill -0 "$pdfsqueezer_pid" 2>/dev/null; do
        if [ "$elapsed" -ge "$PDFSQUEEZER_TIMEOUT" ]; then
            echo "PDF Squeezer timed out after ${PDFSQUEEZER_TIMEOUT}s; terminating process (PID $pdfsqueezer_pid)."
            echo "Check log at $pdfsqueezer_log for details."
            kill "$pdfsqueezer_pid" 2>/dev/null || true
            sleep 1
            kill -9 "$pdfsqueezer_pid" 2>/dev/null || true
            pdfsqueezer_status=124
            break
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    if wait "$pdfsqueezer_pid" 2>/dev/null; then
        :
    else
        pdfsqueezer_status=${pdfsqueezer_status:-$?}
    fi

    if [ "$pdfsqueezer_status" -eq 0 ] && [ -s "$pdfsqueezer_pdf" ]; then
        best_pdf="$pdfsqueezer_pdf"
        best_size=$(get_size "$pdfsqueezer_pdf")
        best_label="PDF Squeezer medium compression"
        echo " • PDF Squeezer size: $(format_size "$best_size")"
    else
        if [ "$pdfsqueezer_status" -ne 0 ]; then
            echo "PDF Squeezer exited with status $pdfsqueezer_status."
        fi
        if [ ! -s "$pdfsqueezer_pdf" ]; then
            echo "PDF Squeezer did not produce a valid output file; keeping previous best."
        fi
        echo "Inspect $pdfsqueezer_log for diagnostics."
    fi
fi

if [ "$HAS_GS" = true ] && [ "$best_pdf" = "$temp_pdf" ]; then
    echo "Trying Ghostscript compression..."
    if gs -sDEVICE=pdfwrite \
          -dCompatibilityLevel=1.4 \
          -dPDFSETTINGS=/ebook \
          -dDownsampleColorImages=true -dColorImageResolution=150 \
          -dDownsampleGrayImages=true -dGrayImageResolution=150 \
          -dDownsampleMonoImages=true -dMonoImageResolution=150 \
          -dNOPAUSE -dQUIET -dBATCH \
          -sOutputFile="$gs_pdf" "$temp_pdf"; then
        gs_size=$(get_size "$gs_pdf")
        echo " • Ghostscript size: $(format_size "$gs_size")"
        if [ "$gs_size" -lt "$best_size" ]; then
            best_pdf="$gs_pdf"
            best_size="$gs_size"
            best_label="Ghostscript-compressed PDF"
        fi
    else
        echo "Ghostscript compression failed; keeping previous best."
    fi
fi

cp "$best_pdf" "$output"
echo "Selected $best_label → $(format_size "$best_size")"

echo "Done! Output saved to $output"
