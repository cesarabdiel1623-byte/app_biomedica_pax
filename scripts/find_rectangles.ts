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
  const ops = await page.getOperatorList();
  
  const OPS = pdfjsLib.OPS;
  const opNames: Record<number, string> = {};
  for (const k in OPS) {
    opNames[OPS[k]] = k;
  }

  const counts: Record<string, number> = {};
  for (let i = 0; i < ops.fnArray.length; i++) {
    const fn = ops.fnArray[i];
    const name = opNames[fn] || String(fn);
    counts[name] = (counts[name] || 0) + 1;
  }
  console.log('Operator counts:', counts);
}

main().catch(console.error);
