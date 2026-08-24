import * as fs from 'fs';
import * as path from 'path';
import {
  renderServiceOrderPdf,
  ServiceOrderPdfData,
  resolveServiceAddress,
} from '../supabase/functions/_shared/service_order_pdf_engine';

async function main() {
  const templatePath = path.resolve(__dirname, '../docs/templates/orden_servicio_base.pdf');
  if (!fs.existsSync(templatePath)) {
    throw new Error(`Template not found at: ${templatePath}`);
  }

  const templateBuffer = fs.readFileSync(templatePath);

  // Real data from ticket TCK-20260817-90B49A25:
  const rawLocation = 'Calle 45A, Interior 927H, Piedra de Agua, Umán, Yucatán, CP 97392';
  const rawAddress = 'Calle 45A';

  const ticketData: ServiceOrderPdfData = {
    ticketNumber: 'TCK-20260817-90B49A25',
    createdAt: '2026-08-17T11:35:47.495793+00:00',

    // Equipment Data
    equipmentName: 'Monitor de signos vitales',
    equipmentBrand: null, // Null in ticket -> empty on PDF
    equipmentModel: 'VS-100',
    serialNumber: null, // Null in ticket -> empty on PDF

    // Service Type: diagnostico -> X in Diagnóstico
    serviceType: 'diagnostico',

    // Equipment Operating: null -> both Sí/No empty
    equipmentOperating: null,

    // Client & Location Data
    clientName: 'cesar puerto', // Resolved from clients(business_name)
    address: resolveServiceAddress(rawAddress, rawLocation), // "Calle 45A, Interior 927H, Piedra de Agua"
    city: 'Umán',
    state: 'Yucatán',
    phone: '99926466748',
    email: 'cesarpuerto10@gmail.com',
    institution: null, // Null in ticket -> empty on PDF

    // Failure Description
    failureDescription: 'El equipo intenta encender, muestra el código E01y se apaga después de unos segundos',

    // Technical fields empty for preliminary order
    workPerformed: null,
    observations: null,
    technicianSignature: null,
    clientSignature: null,
    advisorSignature: null,
  };

  console.log('Rendering calibrated service order PDF with real ticket data...');
  const pdfBytes = await renderServiceOrderPdf(templateBuffer, ticketData);

  const tmpDir = path.resolve(__dirname, '../tmp');
  if (!fs.existsSync(tmpDir)) {
    fs.mkdirSync(tmpDir, { recursive: true });
  }

  const outputPath = path.join(tmpDir, 'TCK-20260817-90B49A25_orden_servicio_preview.pdf');
  fs.writeFileSync(outputPath, Buffer.from(pdfBytes));

  console.log(`✓ PDF preview generated successfully at: ${outputPath}`);
  console.log(`  File size: ${pdfBytes.length} bytes`);
}

main().catch((err) => {
  console.error('Error generating PDF preview:', err);
  process.exit(1);
});
