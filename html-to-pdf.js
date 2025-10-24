// html-to-pdf.js
// FINAL VERSION: No crash, full accuracy, backgrounds, debug

const puppeteer = require('puppeteer');
const path = require('path');
const fs = require('fs');

// === CONFIG ===
const HTML_FILE = process.argv[2] || 'temp.html';
const PDF_FILE = process.argv[3] || 'temp.pdf';
const DEBUG_SCREENSHOT = null; // Disabled

const htmlPath = path.resolve(HTML_FILE);
const pdfPath = path.resolve(PDF_FILE);
const debugPath = DEBUG_SCREENSHOT ? path.resolve(DEBUG_SCREENSHOT) : null;

// === VALIDATION ===
if (!fs.existsSync(htmlPath)) {
  console.error(`Error: ${HTML_FILE} not found at ${htmlPath}`);
  process.exit(1);
}

(async () => {
  console.log('Launching Puppeteer (Chromium)...');
  const browser = await puppeteer.launch({
    headless: true,
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-web-security',
      '--disable-features=IsolateOrigins,site-per-process',
      '--font-render-hinting=medium'
    ]
  });

  const page = await browser.newPage();

  // Emulate print CSS
  await page.emulateMediaType('print');

  // Set viewport to A4 size
  await page.setViewport({ width: 1240, height: 1754 }); // ~A4 at 144 DPI

  console.log(`Loading file://${htmlPath}`);
  await page.goto(`file:${htmlPath}`, {
    waitUntil: 'networkidle0',
    timeout: 30000
  });

  // Wait for fonts
  console.log('Waiting for fonts to load...');
  try {
    await page.evaluate(() => document.fonts.ready);
    console.log('Fonts loaded.');
  } catch (err) {
    console.warn('Font loading failed:', err.message);
  }

  // Wait for content
  console.log('Waiting for content to be ready...');
  try {
    await page.waitForFunction(() => {
      const text = document.body.innerText.trim();
      return text.length > 50;
    }, { timeout: 10000 });
    console.log('Content detected.');
  } catch (err) {
    console.warn('Content wait timed out. Proceeding...');
  }

  // === DEBUG: Screenshot of FIRST PAGE ONLY (safe) ===
  if (DEBUG_SCREENSHOT) {
    console.log(`Saving debug screenshot (first page) → ${debugPath}`);
    await page.screenshot({
      path: debugPath,
      clip: { x: 0, y: 0, width: 1240, height: 1754 }, // A4 size
      type: 'png'
    });
  }

  // === GENERATE PDF (no size limit) ===
  console.log(`Generating PDF → ${pdfPath}`);
  await page.pdf({
    path: pdfPath,
    format: 'A4',
    printBackground: true,
    margin: { top: 0, bottom: 0, left: 0, right: 0 },
    preferCSSPageSize: true,
    scale: 1.0,
    displayHeaderFooter: false
  });

  await browser.close();
  console.log('PDF generated successfully!');
  console.log(`   HTML: ${htmlPath}`);
  console.log(`   PDF:  ${pdfPath}`);
  if (DEBUG_SCREENSHOT) {
    console.log(`   Debug: ${debugPath} (first page only)`);
  }
})();
