import * as fs from 'fs';
import * as path from 'path';
// @ts-ignore
import * as pdfjsLib from 'pdfjs-dist/legacy/build/pdf.mjs';

async function main() {
  const templatePath = path.resolve(__dirname, '../docs/templates/orden_servicio_base.pdf');
  const data = new Uint8Array(fs.readFileSync(templatePath));
  
  const loadingTask = pdfjsLib.getDocument({ data });
  const pdfDoc = await loadingTask.promise;
  const page = await pdfDoc.getPage(1);
  const textContent = await page.getTextContent();
  
  console.log(`--- EXTRACTED TEXT ITEMS (${textContent.items.length}) ---`);
  for (const item of textContent.items) {
    if ('str' in item && item.str.trim().length > 0) {
      const tx = item.transform; // [scaleX, skewY, skewX, scaleY, transX, transY]
      const x = Math.round(tx[4] * 10) / 10;
      const y = Math.round(tx[5] * 10) / 10;
      const w = Math.round(item.width * 10) / 10;
      const h = Math.round(item.height * 10) / 10;
      console.log(`[x=${x}, y=${y}, w=${w}, h=${h}] "${item.str}"`);
    }
  }
}

main().catch(console.error);
