import JSZip from 'jszip';

export interface PptxSlide {
  index: number;
  title: string;
  text: string;
  imageDataUrl?: string;
}

function normalizeZipPath(path: string): string {
  const parts: string[] = [];

  path.split('/').forEach((part) => {
    if (!part || part === '.') return;
    if (part === '..') {
      parts.pop();
      return;
    }
    parts.push(part);
  });

  return parts.join('/');
}

function resolveZipTarget(baseFile: string, target: string): string {
  if (target.startsWith('/')) return normalizeZipPath(target.slice(1));
  const baseDirectory = baseFile.slice(0, baseFile.lastIndexOf('/') + 1);
  return normalizeZipPath(`${baseDirectory}${target}`);
}

function extractSlideText(xml: string): string {
  const document = new DOMParser().parseFromString(xml, 'application/xml');
  const textNodes = Array.from(document.getElementsByTagName('*'))
    .filter((element) => element.localName === 't')
    .map((element) => element.textContent?.trim() || '')
    .filter(Boolean);

  return textNodes.join(' ').replace(/\s+/g, ' ').trim();
}

function firstMeaningfulLine(text: string): string {
  return text.split(/(?<=[.!?])\s+/)[0]?.trim() || text.slice(0, 80).trim();
}

function imageMimeType(path: string): string {
  const extension = path.split('.').pop()?.toLowerCase();
  if (extension === 'jpg' || extension === 'jpeg') return 'image/jpeg';
  if (extension === 'gif') return 'image/gif';
  if (extension === 'webp') return 'image/webp';
  if (extension === 'svg') return 'image/svg+xml';
  return 'image/png';
}

async function readFirstSlideImage(zip: JSZip, slidePath: string): Promise<string | undefined> {
  const slideNumber = slidePath.match(/slide(\d+)\.xml$/i)?.[1];
  if (!slideNumber) return undefined;

  const relationshipsPath = `ppt/slides/_rels/slide${slideNumber}.xml.rels`;
  const relationshipsFile = zip.file(relationshipsPath);
  if (!relationshipsFile) return undefined;

  const relationshipsXml = await relationshipsFile.async('text');
  const relationshipDocument = new DOMParser().parseFromString(relationshipsXml, 'application/xml');
  const imageRelationship = Array.from(relationshipDocument.getElementsByTagName('*')).find((element) => (
    element.localName === 'Relationship' && element.getAttribute('Type')?.toLowerCase().includes('/image')
  ));
  const target = imageRelationship?.getAttribute('Target');
  if (!target) return undefined;

  const imagePath = resolveZipTarget(`ppt/slides/slide${slideNumber}.xml`, target);
  const imageFile = zip.file(imagePath);
  if (!imageFile) return undefined;

  const base64 = await imageFile.async('base64');
  return `data:${imageMimeType(imagePath)};base64,${base64}`;
}

export async function extractPptxSlides(file: File): Promise<PptxSlide[]> {
  if (!file.name.toLowerCase().endsWith('.pptx')) {
    throw new Error('Please upload a .pptx file. Legacy .ppt files must first be saved as .pptx.');
  }

  const zip = await JSZip.loadAsync(file);
  const slidePaths = Object.keys(zip.files)
    .filter((path) => /^ppt\/slides\/slide\d+\.xml$/i.test(path))
    .sort((left, right) => Number(left.match(/slide(\d+)\.xml$/i)?.[1]) - Number(right.match(/slide(\d+)\.xml$/i)?.[1]));

  if (!slidePaths.length) {
    throw new Error('The PPTX does not contain any readable slides.');
  }

  const slides = await Promise.all(slidePaths.map(async (slidePath, index) => {
    const slideFile = zip.file(slidePath);
    if (!slideFile) throw new Error(`Unable to read slide ${index + 1}.`);

    const xml = await slideFile.async('text');
    const text = extractSlideText(xml);
    const imageDataUrl = await readFirstSlideImage(zip, slidePath);

    return {
      index: index + 1,
      title: firstMeaningfulLine(text) || `Slide ${index + 1}`,
      text,
      imageDataUrl
    } satisfies PptxSlide;
  }));

  return slides;
}
