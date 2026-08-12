import * as pdfjsLib from 'pdfjs-dist';
import pdfWorkerUrl from 'pdfjs-dist/build/pdf.worker.min.mjs?url';
import { createWorker } from 'tesseract.js';
import type { PptxSlide } from './pptxParser';

pdfjsLib.GlobalWorkerOptions.workerSrc = pdfWorkerUrl;

export interface PdfExtractionOptions {
  /** Run OCR for pages whose embedded text is missing or too short. */
  runOcr?: boolean;
  onProgress?: (message: string) => void;
}

function firstMeaningfulLine(text: string, pageNumber: number): string {
  return text.split(/(?<=[.!?])\s+/)[0]?.trim().slice(0, 100) || `Page ${pageNumber}`;
}

export async function extractPdfPages(
  file: File,
  options: PdfExtractionOptions = {}
): Promise<PptxSlide[]> {
  if (!file.name.toLowerCase().endsWith('.pdf')) {
    throw new Error('Please upload a .pdf presentation file.');
  }

  const runOcr = options.runOcr === true;
  const document = await pdfjsLib.getDocument({ data: await file.arrayBuffer() }).promise;
  const pages: PptxSlide[] = [];
  const ocrWorker = runOcr
    ? await createWorker('eng', 1, {
      logger: (progress) => {
        if (progress.status === 'recognizing text' && typeof progress.progress === 'number') {
          options.onProgress?.(`OCR is reading page text (${Math.round(progress.progress * 100)}%)...`);
        }
      }
    })
    : null;

  try {
    for (let pageNumber = 1; pageNumber <= document.numPages; pageNumber += 1) {
      options.onProgress?.(`Preparing PDF page ${pageNumber} of ${document.numPages}...`);
      const page = await document.getPage(pageNumber);
      const textContent = await page.getTextContent();
      const embeddedText = textContent.items
        .map((item) => ('str' in item ? item.str : ''))
        .filter(Boolean)
        .join(' ')
        .replace(/\s+/g, ' ')
        .trim();

      // Render at a larger scale when OCR is requested. This gives Tesseract
      // enough pixels for scanned slides while still preserving the page image
      // for the Smartboard viewer and Gemini vision input.
      const viewport = page.getViewport({ scale: runOcr ? 2 : 1.5 });
      const canvas = window.document.createElement('canvas');
      canvas.width = Math.ceil(viewport.width);
      canvas.height = Math.ceil(viewport.height);
      const context = canvas.getContext('2d');

      if (!context) throw new Error(`Unable to render PDF page ${pageNumber}.`);

      await page.render({ canvas, canvasContext: context, viewport }).promise;

      // Digital PDFs already expose selectable text. OCR is used as a fallback
      // for scanned/image-only pages, which is the common case for board scans.
      const shouldOcr = Boolean(ocrWorker && embeddedText.length < 80);
      let ocrText = '';
      if (shouldOcr && ocrWorker) {
        options.onProgress?.(`Running OCR on page ${pageNumber} of ${document.numPages}...`);
        const result = await ocrWorker.recognize(canvas);
        ocrText = result.data.text.replace(/\s+/g, ' ').trim();
      }

      const text = [embeddedText, ocrText]
        .filter(Boolean)
        .join(' ')
        .replace(/\s+/g, ' ')
        .trim();

      pages.push({
        index: pageNumber,
        title: firstMeaningfulLine(text, pageNumber),
        text,
        imageDataUrl: canvas.toDataURL('image/jpeg', 0.86)
      });
    }
  } finally {
    await ocrWorker?.terminate();
  }

  if (!pages.length) throw new Error('The PDF does not contain any readable pages.');
  return pages;
}
