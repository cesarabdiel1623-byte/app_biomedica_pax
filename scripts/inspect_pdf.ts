import { PDFDocument } from 'pdf-lib';
import * as fs from 'fs';
import * as path from 'path';

async function main() {
  const templatePath = path.resolve(__dirname, '../docs/templates/orden_servicio_base.pdf');
  const buffer = fs.readFileSync(templatePath);
  const doc = await PDFDocument.load(buffer);
  
  console.log('Pages count:', doc.getPageCount());
  const page = doc.getPages()[0];
  const { width, height } = page.getSize();
  console.log(`Page dimensions: width=${width}pt, height=${height}pt`);
}

main().catch(console.error);
