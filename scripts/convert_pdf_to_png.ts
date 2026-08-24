import * as fs from 'fs';
import * as path from 'path';
// @ts-ignore
import * as pdfjsLib from 'pdfjs-dist/legacy/build/pdf.mjs';
// @ts-ignore
import { createCanvas } from '@napi-rs/canvas';

async function main() {
  const pdfPath = path.resolve(__dirname, '../tmp/TCK-20260817-90B49A25_orden_servicio_preview.pdf');
  const data = new Uint8Array(fs.readFileSync(pdfPath));
  
  const loadingTask = pdfjsLib.getDocument({ data });
  const pdfDoc = await loadingTask.promise;
  const page = await pdfDoc.getPage(1);
  
  const scale = 2.0; // 2x resolution
  const viewport = page.getViewport({ scale });
  
  const canvas = createCanvas(viewport.width, viewport.height);
  const ctx = canvas.getContext('2d');
  
  const renderContext = {
    canvasContext: ctx,
    viewport: viewport,
  };
  
  await page.render(renderContext).promise;
  
  const pngPath = path.resolve(__dirname, '../tmp/TCK-20260817-90B49A25_orden_servicio_preview.png');
  fs.writeFileSync(pngPath, canvas.toBuffer('image/png'));
  console.log('✓ Converted PDF to PNG at:', pngPath);
}

main().catch(console.error);
