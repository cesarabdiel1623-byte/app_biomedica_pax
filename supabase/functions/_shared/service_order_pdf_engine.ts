import { PDFDocument, rgb, StandardFonts, PDFFont, PDFPage } from 'npm:pdf-lib';

export interface ServiceOrderPdfData {
  ticketNumber?: string;
  createdAt?: string | Date;
  completedAt?: string | Date;

  // Equipment Info
  equipmentName?: string | null;
  equipmentBrand?: string | null;
  equipmentModel?: string | null;
  serialNumber?: string | null;

  // Service Type
  serviceType?: 'preventivo' | 'correctivo' | 'diagnostico' | 'otro' | string | null;
  otherServiceType?: string | null;

  // Equipment Operating
  equipmentOperating?: boolean | null;

  // Client & Location
  clientName?: string | null;
  address?: string | null;
  city?: string | null;
  state?: string | null;
  phone?: string | null;
  email?: string | null;
  institution?: string | null;

  // Technical details
  failureDescription?: string | null;
  workPerformed?: string | null;
  observations?: string | null;

  // Signatures (Base64 PNG or URL) - optional
  clientSignature?: string | null;
  technicianSignature?: string | null;
  advisorSignature?: string | null;
}

export interface FittedTextOptions {
  x: number;
  y: number;
  maxWidth: number;
  preferredFontSize?: number;
  minFontSize?: number;
  font?: PDFFont;
  color?: ReturnType<typeof rgb>;
}

export interface CheckboxCenter {
  centerX: number;
  centerY: number;
  size?: number;
}

export const SERVICE_ORDER_COORDS = {
  date: {
    daySlot: { centerX: 421.0, y: 681.5, maxWidth: 26 },
    monthSlot: { centerX: 466.0, y: 681.5, maxWidth: 20 },
  },
  equipment: {
    name: { x: 88.0, y: 653.5, maxWidth: 195.0, preferredFontSize: 8.0, minFontSize: 6.5 },
    brand: { x: 85.0, y: 630.5, maxWidth: 198.0, preferredFontSize: 8.0, minFontSize: 6.5 },
    model: { x: 89.0, y: 610.5, maxWidth: 194.0, preferredFontSize: 8.0, minFontSize: 6.5 },
    serialNumber: { x: 128.0, y: 583.5, maxWidth: 155.0, preferredFontSize: 8.0, minFontSize: 6.5 },
  },
  serviceType: {
    preventivo: { centerX: 384.5, centerY: 651.5, size: 7.5 },
    correctivo: { centerX: 384.5, centerY: 635.5, size: 7.5 },
    diagnostico: { centerX: 384.5, centerY: 619.5, size: 7.5 },
    otro: { centerX: 384.5, centerY: 603.5, size: 7.5 },
    otroText: { x: 412.0, y: 603.5, maxWidth: 140.0, preferredFontSize: 8.0, minFontSize: 6.5 },
  },
  operating: {
    yes: { centerX: 442.0, centerY: 579.5, size: 7.5 },
    no: { centerX: 504.5, centerY: 579.5, size: 7.5 },
  },
  client: {
    name: { x: 140.0, y: 533.0, maxWidth: 175.0, preferredFontSize: 8.0, minFontSize: 6.5 },
    address: { x: 375.0, y: 533.0, maxWidth: 180.0, preferredFontSize: 7.5, minFontSize: 6.0 },
    city: { x: 88.0, y: 509.5, maxWidth: 225.0, preferredFontSize: 8.0, minFontSize: 6.5 },
    state: { x: 368.0, y: 509.5, maxWidth: 185.0, preferredFontSize: 8.0, minFontSize: 6.5 },
    phone: { x: 80.0, y: 499.5, maxWidth: 88.0, preferredFontSize: 7.5, minFontSize: 6.0 },
    email: { x: 232.0, y: 499.5, maxWidth: 120.0, preferredFontSize: 7.0, minFontSize: 5.5 },
    institution: { x: 450.0, y: 499.5, maxWidth: 105.0, preferredFontSize: 7.5, minFontSize: 6.0 },
  },
  failureDescription: {
    lines: [
      { x: 158.0, y: 467.5, maxWidth: 395.0, preferredFontSize: 8.0, minFontSize: 6.5 },
      { x: 48.0, y: 455.5, maxWidth: 505.0, preferredFontSize: 8.0, minFontSize: 6.5 },
      { x: 48.0, y: 443.5, maxWidth: 505.0, preferredFontSize: 8.0, minFontSize: 6.5 },
      { x: 48.0, y: 429.5, maxWidth: 505.0, preferredFontSize: 8.0, minFontSize: 6.5 },
    ],
  },
  workPerformed: {
    lines: [
      { x: 198.0, y: 405.5, maxWidth: 355.0, preferredFontSize: 8.0, minFontSize: 6.5 },
      { x: 48.0, y: 393.5, maxWidth: 505.0, preferredFontSize: 8.0, minFontSize: 6.5 },
      { x: 48.0, y: 379.5, maxWidth: 505.0, preferredFontSize: 8.0, minFontSize: 6.5 },
      { x: 48.0, y: 365.5, maxWidth: 505.0, preferredFontSize: 8.0, minFontSize: 6.5 },
      { x: 48.0, y: 351.5, maxWidth: 505.0, preferredFontSize: 8.0, minFontSize: 6.5 },
    ],
  },
  observations: {
    lines: [
      { x: 122.0, y: 306.5, maxWidth: 430.0, preferredFontSize: 8.0, minFontSize: 6.5 },
      { x: 48.0, y: 291.5, maxWidth: 505.0, preferredFontSize: 8.0, minFontSize: 6.5 },
      { x: 48.0, y: 276.5, maxWidth: 505.0, preferredFontSize: 8.0, minFontSize: 6.5 },
      { x: 48.0, y: 261.5, maxWidth: 505.0, preferredFontSize: 8.0, minFontSize: 6.5 },
      { x: 48.0, y: 246.5, maxWidth: 505.0, preferredFontSize: 8.0, minFontSize: 6.5 },
    ],
  },
};

const SPANISH_FULL_MONTHS = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

const SPANISH_ABBR_MONTHS = [
  'ene.', 'feb.', 'mar.', 'abr.', 'mayo', 'jun.',
  'jul.', 'ago.', 'sep.', 'oct.', 'nov.', 'dic.',
];

/**
 * Renders a single line of fitted text with smooth downscaling and controlled truncation.
 */
export function drawFittedText(
  page: PDFPage,
  text: string | null | undefined,
  options: FittedTextOptions
): void {
  if (!text || text.trim() === '') return;
  const clean = text.trim();
  const font = options.font!;
  const color = options.color ?? rgb(0.12, 0.16, 0.22);
  const preferredSize = options.preferredFontSize ?? 8.0;
  const minSize = options.minFontSize ?? 6.0;
  const maxWidth = options.maxWidth;

  let currentSize = preferredSize;
  let textWidth = font.widthOfTextAtSize(clean, currentSize);

  if (textWidth > maxWidth) {
    const requiredSize = (maxWidth / textWidth) * preferredSize;
    if (requiredSize >= minSize) {
      currentSize = Math.floor(requiredSize * 10) / 10;
      textWidth = font.widthOfTextAtSize(clean, currentSize);
    } else {
      currentSize = minSize;
      let truncated = clean;
      while (truncated.length > 2 && font.widthOfTextAtSize(`${truncated}...`, currentSize) > maxWidth) {
        truncated = truncated.slice(0, -1).trim();
      }
      page.drawText(`${truncated}...`, {
        x: options.x,
        y: options.y,
        size: currentSize,
        font,
        color,
      });
      return;
    }
  }

  page.drawText(clean, {
    x: options.x,
    y: options.y,
    size: currentSize,
    font,
    color,
  });
}

/**
 * Draws a centered 'X' inside a checkbox square.
 */
export function drawCheckboxMark(
  page: PDFPage,
  checkbox: CheckboxCenter,
  boldFont: PDFFont,
  color: ReturnType<typeof rgb>
): void {
  const size = checkbox.size ?? 7.5;
  const charWidth = boldFont.widthOfTextAtSize('X', size);
  const x = checkbox.centerX - charWidth / 2;
  const y = checkbox.centerY - size / 2.8;

  page.drawText('X', {
    x,
    y,
    size,
    font: boldFont,
    color,
  });
}

/**
 * Word-wraps text across multiple distinct line definitions, respecting explicit newlines (\n).
 */
export function drawMultilineBlock(
  page: PDFPage,
  text: string | null | undefined,
  lines: Array<{ x: number; y: number; maxWidth: number; preferredFontSize?: number; minFontSize?: number }>,
  font: PDFFont,
  color: ReturnType<typeof rgb>
): void {
  if (!text || text.trim() === '' || lines.length === 0) return;

  // Normalizar saltos de línea (CRLF -> LF)
  const normalized = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n').trim();
  const rawParagraphs = normalized.split('\n');

  const paragraphs: string[] = [];
  for (const p of rawParagraphs) {
    const trimmed = p.trim();
    if (trimmed.length > 0) {
      paragraphs.push(trimmed);
    }
  }

  if (paragraphs.length === 0) return;

  let lineIdx = 0;

  for (let pIdx = 0; pIdx < paragraphs.length; pIdx++) {
    if (lineIdx >= lines.length) break;

    const paragraph = paragraphs[pIdx];
    const words = paragraph.split(/\s+/).filter(w => w.length > 0);
    if (words.length === 0) continue;

    let currentWordIndex = 0;

    while (currentWordIndex < words.length && lineIdx < lines.length) {
      const lineDef = lines[lineIdx];
      const fontSize = lineDef.preferredFontSize ?? 8.0;
      const maxWidth = lineDef.maxWidth;

      let lineText = words[currentWordIndex];
      currentWordIndex++;

      // Si una sola palabra excede el maxWidth disponible, dividirla o truncarla de forma determinista
      if (font.widthOfTextAtSize(lineText, fontSize) > maxWidth) {
        let chunk = '';
        let remainder = '';
        for (let cIdx = 0; cIdx < lineText.length; cIdx++) {
          const testChunk = chunk + lineText[cIdx];
          if (font.widthOfTextAtSize(testChunk, fontSize) <= maxWidth) {
            chunk = testChunk;
          } else {
            remainder = lineText.slice(cIdx);
            break;
          }
        }
        if (chunk.length > 0) {
          lineText = chunk;
          if (remainder.length > 0) {
            words.splice(currentWordIndex, 0, remainder);
          }
        } else {
          while (lineText.length > 1 && font.widthOfTextAtSize(`${lineText}...`, fontSize) > maxWidth) {
            lineText = lineText.slice(0, -1);
          }
          lineText = `${lineText}...`;
        }
      }

      while (currentWordIndex < words.length) {
        const nextWord = words[currentWordIndex];
        const candidate = `${lineText} ${nextWord}`;
        if (font.widthOfTextAtSize(candidate, fontSize) <= maxWidth) {
          lineText = candidate;
          currentWordIndex++;
        } else {
          break;
        }
      }

      const isLastAvailableLine = (lineIdx === lines.length - 1);
      const hasMoreInParagraph = (currentWordIndex < words.length);
      const hasMoreParagraphs = (pIdx < paragraphs.length - 1);

      // Truncado determinista y seguro con ellipsis si excede físicamente el área asignada
      if (isLastAvailableLine && (hasMoreInParagraph || hasMoreParagraphs)) {
        while (lineText.length > 2 && font.widthOfTextAtSize(`${lineText}...`, fontSize) > maxWidth) {
          lineText = lineText.slice(0, -1).trim();
        }
        lineText = `${lineText}...`;
      }

      page.drawText(lineText, {
        x: lineDef.x,
        y: lineDef.y,
        size: fontSize,
        font,
        color,
      });

      lineIdx++;
    }
  }
}

/**
 * Formats a clean street address without duplicating city/state if already present.
 */
export function resolveServiceAddress(rawAddress?: string | null, rawLocation?: string | null): string {
  if (!rawAddress && !rawLocation) return '';
  if (rawLocation && rawLocation.trim().length > 0) {
    const parts = rawLocation.split(',').map((p) => p.trim());
    const filtered = parts.filter((part) => {
      const lower = part.toLowerCase();
      return !lower.startsWith('cp ') &&
             !lower.startsWith('c.p.') &&
             lower !== 'yucatán' &&
             lower !== 'yucatan' &&
             lower !== 'mexico' &&
             lower !== 'méxico' &&
             lower !== 'umán' &&
             lower !== 'uman' &&
             lower !== 'mérida' &&
             lower !== 'merida';
    });
    if (filtered.length > 0) {
      return filtered.join(', ');
    }
  }
  return (rawAddress ?? '').trim();
}

/**
 * Main service order PDF rendering function.
 */
export async function renderServiceOrderPdf(
  templateBuffer: Uint8Array | ArrayBuffer,
  data: ServiceOrderPdfData
): Promise<Uint8Array> {
  const doc = await PDFDocument.load(templateBuffer);
  const page = doc.getPages()[0];
  const regularFont = await doc.embedFont(StandardFonts.Helvetica);
  const boldFont = await doc.embedFont(StandardFonts.HelveticaBold);
  const textColor = rgb(0.12, 0.16, 0.22); // crisp, readable dark charcoal
  const checkColor = rgb(0.08, 0.18, 0.35); // crisp bold navy for X

  // 1. FECHA (Día y Mes adaptativo en sus espacios exactos)
  const dateObj = data.completedAt ? new Date(data.completedAt) : data.createdAt ? new Date(data.createdAt) : null;
  if (dateObj && !isNaN(dateObj.getTime())) {
    const dayStr = dateObj.getDate().toString();
    const dayWidth = regularFont.widthOfTextAtSize(dayStr, 8.5);
    const dayX = SERVICE_ORDER_COORDS.date.daySlot.centerX - dayWidth / 2;

    page.drawText(dayStr, {
      x: dayX,
      y: SERVICE_ORDER_COORDS.date.daySlot.y,
      size: 8.5,
      font: regularFont,
      color: textColor,
    });

    const monthIdx = dateObj.getMonth();
    const fullMonth = SPANISH_FULL_MONTHS[monthIdx];
    const abbrMonth = SPANISH_ABBR_MONTHS[monthIdx];
    const maxMonthWidth = SERVICE_ORDER_COORDS.date.monthSlot.maxWidth;

    let chosenMonth = fullMonth;
    let monthSize = 7.5;

    // Check if full month fits within maxMonthWidth
    if (regularFont.widthOfTextAtSize(fullMonth, monthSize) > maxMonthWidth) {
      chosenMonth = abbrMonth;
      monthSize = 7.5;
      if (regularFont.widthOfTextAtSize(chosenMonth, monthSize) > maxMonthWidth) {
        monthSize = 6.8;
      }
    }

    const monthWidth = regularFont.widthOfTextAtSize(chosenMonth, monthSize);
    const monthX = SERVICE_ORDER_COORDS.date.monthSlot.centerX - monthWidth / 2;

    page.drawText(chosenMonth, {
      x: monthX,
      y: SERVICE_ORDER_COORDS.date.monthSlot.y,
      size: monthSize,
      font: regularFont,
      color: textColor,
    });
  }

  // 2. DATOS DEL EQUIPO
  drawFittedText(page, data.equipmentName, { ...SERVICE_ORDER_COORDS.equipment.name, font: regularFont, color: textColor });
  drawFittedText(page, data.equipmentBrand, { ...SERVICE_ORDER_COORDS.equipment.brand, font: regularFont, color: textColor });
  drawFittedText(page, data.equipmentModel, { ...SERVICE_ORDER_COORDS.equipment.model, font: regularFont, color: textColor });
  drawFittedText(page, data.serialNumber, { ...SERVICE_ORDER_COORDS.equipment.serialNumber, font: regularFont, color: textColor });

  // 3. TIPO DE SERVICIO (Casillas X)
  const normalizedType = (data.serviceType ?? '').toLowerCase().trim();
  if (normalizedType === 'preventivo') {
    drawCheckboxMark(page, SERVICE_ORDER_COORDS.serviceType.preventivo, boldFont, checkColor);
  } else if (normalizedType === 'correctivo' || normalizedType === 'reparacion') {
    drawCheckboxMark(page, SERVICE_ORDER_COORDS.serviceType.correctivo, boldFont, checkColor);
  } else if (normalizedType === 'diagnostico') {
    drawCheckboxMark(page, SERVICE_ORDER_COORDS.serviceType.diagnostico, boldFont, checkColor);
  } else if (normalizedType === 'otro' || normalizedType.length > 0) {
    drawCheckboxMark(page, SERVICE_ORDER_COORDS.serviceType.otro, boldFont, checkColor);
    if (data.otherServiceType) {
      drawFittedText(page, data.otherServiceType, { ...SERVICE_ORDER_COORDS.serviceType.otroText, font: regularFont, color: textColor });
    }
  }

  // 4. EQUIPO OPERANDO (SÍ / NO)
  if (data.equipmentOperating === true) {
    drawCheckboxMark(page, SERVICE_ORDER_COORDS.operating.yes, boldFont, checkColor);
  } else if (data.equipmentOperating === false) {
    drawCheckboxMark(page, SERVICE_ORDER_COORDS.operating.no, boldFont, checkColor);
  }

  // 5. DATOS DEL CLIENTE Y UBICACIÓN
  drawFittedText(page, data.clientName, { ...SERVICE_ORDER_COORDS.client.name, font: regularFont, color: textColor });
  drawFittedText(page, data.address, { ...SERVICE_ORDER_COORDS.client.address, font: regularFont, color: textColor });
  drawFittedText(page, data.city, { ...SERVICE_ORDER_COORDS.client.city, font: regularFont, color: textColor });
  drawFittedText(page, data.state, { ...SERVICE_ORDER_COORDS.client.state, font: regularFont, color: textColor });
  drawFittedText(page, data.phone, { ...SERVICE_ORDER_COORDS.client.phone, font: regularFont, color: textColor });
  drawFittedText(page, data.email, { ...SERVICE_ORDER_COORDS.client.email, font: regularFont, color: textColor });
  drawFittedText(page, data.institution, { ...SERVICE_ORDER_COORDS.client.institution, font: regularFont, color: textColor });

  // 6. DESCRIPCIÓN DE LA FALLA (Multilínea)
  drawMultilineBlock(page, data.failureDescription, SERVICE_ORDER_COORDS.failureDescription.lines, regularFont, textColor);

  // 7. TRABAJO REALIZADO (Multilínea)
  drawMultilineBlock(page, data.workPerformed, SERVICE_ORDER_COORDS.workPerformed.lines, regularFont, textColor);

  // 8. OBSERVACIONES (Multilínea)
  drawMultilineBlock(page, data.observations, SERVICE_ORDER_COORDS.observations.lines, regularFont, textColor);

  return doc.save();
}
