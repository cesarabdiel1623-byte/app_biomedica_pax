import * as fs from 'fs';
import * as path from 'path';
import {
  renderServiceOrderPdf,
  ServiceOrderPdfData,
} from '../supabase/functions/_shared/service_order_pdf_engine';
// @ts-ignore
import * as pdfjsLib from 'pdfjs-dist/legacy/build/pdf.mjs';
// @ts-ignore
import { createCanvas } from '@napi-rs/canvas';

async function renderPdfToPng(pdfBuffer: Uint8Array, pngPath: string) {
  const loadingTask = pdfjsLib.getDocument({ data: new Uint8Array(pdfBuffer) });
  const pdfDoc = await loadingTask.promise;
  const page = await pdfDoc.getPage(1);
  const scale = 2.0;
  const viewport = page.getViewport({ scale });
  const canvas = createCanvas(viewport.width, viewport.height);
  const ctx = canvas.getContext('2d');
  await page.render({ canvasContext: ctx, viewport }).promise;
  fs.writeFileSync(pngPath, canvas.toBuffer('image/png'));
}

async function main() {
  const templatePath = path.resolve(__dirname, '../docs/templates/orden_servicio_base.pdf');
  const templateBuffer = fs.readFileSync(templatePath);
  const tmpDir = path.resolve(__dirname, '../tmp');
  if (!fs.existsSync(tmpDir)) fs.mkdirSync(tmpDir, { recursive: true });

  const scenarios: Array<{ name: string; data: ServiceOrderPdfData }> = [
    {
      name: 'scenario_A_preventivo_septiembre_multiline',
      data: {
        ticketNumber: 'TCK-20260915-PREV01',
        createdAt: '2026-09-15T10:00:00Z',
        completedAt: '2026-09-15T14:30:00Z',
        equipmentName: 'Desfibrilador bifásico con marcapasos externo avanzado',
        equipmentBrand: 'Mindray Medical Corp',
        equipmentModel: 'BeneHeart D6 Series Pro',
        serialNumber: 'SN-9988221100-MX',
        serviceType: 'preventivo',
        equipmentOperating: true,
        clientName: 'Hospital General Dr. Agustín O’Horán',
        address: 'Av. Itzaes por Jacinto Canek #123, Edificio A, Piso 3',
        city: 'Mérida',
        state: 'Yucatán',
        phone: '9991234567',
        email: 'biomedica.contacto@hospitalgeneral.gob.mx',
        institution: 'Servicios de Salud de Yucatán (SSY)',
        failureDescription: 'Mantenimiento preventivo semestral programado según póliza vigente. Se requiere calibración de descargas en 50J, 100J, 200J y 360J, así como revisión de paletas y prueba de batería interna.',
        workPerformed: 'Se realizó limpieza interna y externa del equipo, ajuste de conectores de ECG, calibración y prueba de descarga con analizador biomédico Fluke Impulse 7000DP. Se verificó sincronía de cardioversión y respuesta de marcapasos.',
        observations: 'El equipo se entrega operando dentro de parámetros de fabricante. Batería en estado óptimo con 96% de capacidad de retención. Próximo mantenimiento preventivo sugerido en 6 meses.',
      },
    },
    {
      name: 'scenario_B_correctivo_noviembre_stress',
      data: {
        ticketNumber: 'TCK-20261120-CORR02',
        createdAt: '2026-11-20T08:15:00Z',
        completedAt: '2026-11-21T18:00:00Z',
        equipmentName: 'Ultrasonido Doppler Color 4D HD Live',
        equipmentBrand: 'General Electric Healthcare',
        equipmentModel: 'Voluson E10 BT20 Elite High Performance',
        serialNumber: 'GE-VOLUSON-E10-77665544',
        serviceType: 'correctivo',
        equipmentOperating: false,
        clientName: 'Centro Ginecológico y Obstétrico Peninsular S.A. de C.V.',
        address: 'Calle 50 #402 x 33 y 35, Consultorio 12, Fracc. Montecristo',
        city: 'Mérida',
        state: 'Yucatán',
        phone: '9998765432',
        email: 'administracion@ginecopensinsular.com.mx',
        institution: 'Clínica Especializada Montecristo',
        failureDescription: 'El equipo no enciende tras descarga eléctrica. Se escuchan relevadores internos pero no envía señal a los monitores principales ni al panel táctil flotante.',
        workPerformed: 'Diagnóstico en fuente de poder conmutada auxiliar. Se reemplazó módulo rectificador dañado y fusible de alta velocidad 10A. Se realizó reprogramación de firmware de arranque y pruebas de transductores volumétrico y endocavitario.',
        observations: 'Se recomienda instalar regulador de voltaje con aislamiento galvánico de al menos 3kVA para proteger contra fluctuaciones en la red eléctrica del quirófano.',
      },
    },
    {
      name: 'scenario_C_diagnostico_diciembre',
      data: {
        ticketNumber: 'TCK-20261205-DIAG03',
        createdAt: '2026-12-05T12:00:00Z',
        equipmentName: 'Ventilador Mecánico Pulmonar de Cuidados Intensivos',
        equipmentBrand: 'Hamilton Medical AG',
        equipmentModel: 'Hamilton G5 Advanced ICU',
        serialNumber: 'HAM-G5-2026-8899',
        serviceType: 'diagnostico',
        equipmentOperating: null,
        clientName: 'Instituto de Especialidades Médicas del Sureste',
        address: 'Calle 60 Norte #299, Zona Industrial',
        city: 'Mérida',
        state: 'Yucatán',
        phone: '9993332211',
        email: 'soporte.terapia.intensiva@institutosureste.org',
        institution: 'Torre Médica Sureste Piso 5',
        failureDescription: 'Alarma constante de presión pico alta y error de calibración en celda de oxígeno galvánica. El equipo rechaza el auto-test de flujo expiratorio.',
        workPerformed: null,
        observations: null,
      },
    },
  ];

  for (const s of scenarios) {
    console.log(`Testing stress scenario: ${s.name}...`);
    const pdfBytes = await renderServiceOrderPdf(templateBuffer, s.data);
    const pdfOut = path.join(tmpDir, `${s.name}.pdf`);
    const pngOut = path.join(tmpDir, `${s.name}.png`);
    fs.writeFileSync(pdfOut, Buffer.from(pdfBytes));
    await renderPdfToPng(pdfBytes, pngOut);
    console.log(`✓ Generated ${pdfOut} and ${pngOut}`);
  }

  console.log('✓ All stress scenarios tested successfully!');
}

main().catch(console.error);
