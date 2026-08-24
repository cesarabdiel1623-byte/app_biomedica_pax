import { PDFDocument, rgb, StandardFonts } from 'pdf-lib';
import * as fs from 'fs';
import * as path from 'path';

async function main() {
  const templatePath = path.resolve(__dirname, '../docs/templates/orden_servicio_base.pdf');
  const buffer = fs.readFileSync(templatePath);
  const doc = await PDFDocument.load(buffer);
  const page = doc.getPages()[0];
  const font = await doc.embedFont(StandardFonts.Helvetica);
  
  const { width, height } = page.getSize();
  
  // Draw grid
  for (let x = 0; x <= width; x += 50) {
    page.drawLine({
      start: { x, y: 0 },
      end: { x, y: height },
      color: rgb(0.8, 0.8, 1),
      thickness: 0.5,
    });
    page.drawText(`${x}`, { x: x + 2, y: 10, size: 6, font, color: rgb(0, 0, 0.8) });
    page.drawText(`${x}`, { x: x + 2, y: height - 15, size: 6, font, color: rgb(0, 0, 0.8) });
  }

  for (let y = 0; y <= height; y += 25) {
    page.drawLine({
      start: { x: 0, y },
      end: { x: width, y },
      color: rgb(0.8, 0.8, 1),
      thickness: 0.5,
    });
    page.drawText(`${y}`, { x: 5, y: y + 2, size: 6, font, color: rgb(0, 0, 0.8) });
    page.drawText(`${y}`, { x: width - 25, y: y + 2, size: 6, font, color: rgb(0, 0, 0.8) });
  }

  const tmpDir = path.resolve(__dirname, '../tmp');
  if (!fs.existsSync(tmpDir)) fs.mkdirSync(tmpDir, { recursive: true });
  
  const outPath = path.join(tmpDir, 'grid_overlay.pdf');
  fs.writeFileSync(outPath, await doc.save());
  console.log('Saved grid overlay to:', outPath);
}

main().catch(console.error);
