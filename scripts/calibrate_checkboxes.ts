import { PDFDocument, rgb, StandardFonts } from 'pdf-lib';
import * as fs from 'fs';
import * as path from 'path';

async function main() {
  const templatePath = path.resolve(__dirname, '../docs/templates/orden_servicio_base.pdf');
  const buffer = fs.readFileSync(templatePath);
  const doc = await PDFDocument.load(buffer);
  const page = doc.getPages()[0];
  const font = await doc.embedFont(StandardFonts.HelveticaBold);
  const regularFont = await doc.embedFont(StandardFonts.Helvetica);

  // Let's test checkbox positions:
  // "Mantenimiento preventivo" is at [x=392.7, y=648.7]. Checkbox is likely at x=382 (left of text) or x=500+ (right).
  // "Mantenimiento correctivo" is at [x=392.7, y=632.7].
  // "Diagnóstico" is at [x=392.7, y=617.4].
  // "SÍ" is at [x=427.7, y=577.1].
  // "NO" is at [x=484, y=577.1].

  // Let's draw test markers around these areas
  const testMarkers = [
    // Checkbox candidates for Preventivo (x ~ 382, y ~ 648) or (x ~ 490, y ~ 648)
    { label: 'P1', x: 382.5, y: 648.7 },
    { label: 'P2', x: 495, y: 648.7 },
    // Checkbox candidates for Correctivo (x ~ 382, y ~ 632.7)
    { label: 'C1', x: 382.5, y: 632.7 },
    // Checkbox candidates for Diagnóstico (x ~ 382, y ~ 617.4)
    { label: 'D1', x: 382.5, y: 617.4 },
    // SÍ candidates (x ~ 415 or 437)
    { label: 'S1', x: 416, y: 577.1 },
    { label: 'S2', x: 438, y: 577.1 },
    // NO candidates (x ~ 472 or 498)
    { label: 'N1', x: 472, y: 577.1 },
    { label: 'N2', x: 498, y: 577.1 },
  ];

  for (const m of testMarkers) {
    page.drawText('X', {
      x: m.x,
      y: m.y,
      size: 9,
      font,
      color: rgb(0.9, 0.1, 0.1),
    });
  }

  const tmpDir = path.resolve(__dirname, '../tmp');
  if (!fs.existsSync(tmpDir)) fs.mkdirSync(tmpDir, { recursive: true });

  fs.writeFileSync(path.join(tmpDir, 'calibration_test.pdf'), await doc.save());
  console.log('Saved calibration test to tmp/calibration_test.pdf');
}

main().catch(console.error);
