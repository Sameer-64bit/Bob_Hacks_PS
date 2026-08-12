import type {
  DiagramSnippet,
  FormulaItem,
  Lecture,
  LectureChapter,
  LectureSourceMeta,
  TargetLanguage,
  TranscriptSegment,
  WhiteboardPage
} from '../types';
import type { PptxSlide } from './pptxParser';

export interface AnalysisMetaInput {
  source_file?: string;
  source_type?: string;
  duration_seconds?: number | null;
  page_count?: number | null;
  language?: string;
  mode?: string;
  processed_at?: string;
  tool_version?: string;
}

export interface AnalysisKeyConceptInput {
  concept?: string;
  explanation?: string;
  first_seen?: { timestamp?: number | null; page?: number | null };
}

export interface AnalysisChapterInput {
  title?: string;
  start?: { timestamp?: number | null; page?: number | null };
}

export interface AnalysisSpokenContentInput {
  start?: number;
  end?: number;
  text?: string;
}

export interface AnalysisSectionInput {
  id?: string;
  kind?: string;
  title?: string;
  location?: {
    timestamp_ranges?: Array<[number, number]> | null;
    pages?: number[] | null;
  };
  visual_content_markdown?: string;
  raw_ocr_text?: string;
  spoken_content?: AnalysisSpokenContentInput[];
  section_summary?: string;
  asset_path?: string | null;
}

export interface AnalysisTranscriptInput {
  start?: number;
  end?: number;
  text?: string;
}

export interface AnalysisDocument {
  meta?: AnalysisMetaInput;
  summary?: {
    global?: string;
    one_liner?: string;
    key_concepts?: AnalysisKeyConceptInput[];
    chapters?: AnalysisChapterInput[];
  };
  sections?: AnalysisSectionInput[];
  transcript?: AnalysisTranscriptInput[];
}

function removeJsonComments(value: string): string {
  let output = '';
  let inString = false;
  let escaped = false;

  for (let index = 0; index < value.length; index += 1) {
    const character = value[index];
    const nextCharacter = value[index + 1];

    if (inString) {
      output += character;
      if (escaped) {
        escaped = false;
      } else if (character === '\\') {
        escaped = true;
      } else if (character === '"') {
        inString = false;
      }
      continue;
    }

    if (character === '"') {
      inString = true;
      output += character;
    } else if (character === '/' && nextCharacter === '/') {
      while (index < value.length && value[index] !== '\n') index += 1;
      output += '\n';
    } else if (character === '/' && nextCharacter === '*') {
      index += 2;
      while (index < value.length && !(value[index] === '*' && value[index + 1] === '/')) index += 1;
      index += 1;
    } else {
      output += character;
    }
  }

  return output.replace(/,\s*([}\]])/g, '$1');
}

export function parseAnalysisDocument(value: string): unknown {
  let normalized = value.trim();

  if (normalized.startsWith('```')) {
    normalized = normalized
      .replace(/^```(?:json)?\s*/i, '')
      .replace(/\s*```$/, '')
      .trim();
  }

  try {
    return JSON.parse(normalized) as unknown;
  } catch {
    return JSON.parse(removeJsonComments(normalized)) as unknown;
  }
}

const ALL_LANGUAGES: TargetLanguage[] = ['en', 'hi', 'bn', 'ar'];

function languageRecord<T>(value: T): Record<TargetLanguage, T> {
  return ALL_LANGUAGES.reduce((record, language) => {
    record[language] = value;
    return record;
  }, {} as Record<TargetLanguage, T>);
}

function textOrFallback(value: unknown, fallback: string): string {
  const cleaned = typeof value === 'string' ? cleanImportedText(value) : '';
  return cleaned ? cleaned : fallback;
}

function stripExtension(filename: string): string {
  return filename.replace(/\.[^/.]+$/, '').replace(/[_-]+/g, ' ').trim();
}

function formatTimestamp(seconds?: number | null): string {
  if (typeof seconds !== 'number' || !Number.isFinite(seconds)) return '—';
  const totalSeconds = Math.max(0, Math.round(seconds));
  const minutes = Math.floor(totalSeconds / 60);
  const remainder = totalSeconds % 60;
  return `${String(minutes).padStart(2, '0')}:${String(remainder).padStart(2, '0')}`;
}

function formatDuration(seconds?: number | null): string {
  if (typeof seconds !== 'number' || !Number.isFinite(seconds)) return '—';
  const totalMinutes = Math.round(seconds / 60);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  return hours ? `${hours}h ${minutes}m` : `${minutes}m`;
}

function formatProcessedDate(value?: string): string {
  if (!value) return '—';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? value.slice(0, 10) : date.toISOString().slice(0, 10);
}

function escapeXml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

/**
 * OCR exports sometimes encode handwritten star/rating marks as unsupported
 * LaTeX commands such as `\\text{\\textasteriskcentered}`. Those commands are
 * not meaningful lecture prose, so remove them before displaying or sending
 * imported content to the AI service.
 */
export function cleanImportedText(value: string): string {
  return value
    .replace(/\$(?:[^$\n]*\\text\s*\{\s*\\textasteriskcentered\s*\}[^$\n]*)\$/gi, '')
    .replace(/\\text\s*\{\s*\\textasteriskcentered\s*\}/gi, '')
    .replace(/\\textasteriskcentered/gi, '')
    .replace(/\btextasteriskcentered\b/gi, '')
    .replace(/[ \t]{2,}/g, ' ')
    .replace(/\s+([,.;:)\]])/g, '$1')
    .replace(/([([{])\s+/g, '$1')
    .replace(/\(\s*\)|\[\s*\]|\{\s*\}/g, '')
    .replace(/\n[ \t]+/g, '\n')
    .trim();
}

function sanitizeUnknown(value: unknown): unknown {
  if (typeof value === 'string') return cleanImportedText(value);
  if (Array.isArray(value)) return value.map((item) => sanitizeUnknown(item));
  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([key, item]) => [key, sanitizeUnknown(item)])
    );
  }
  return value;
}

export function sanitizeAnalysisDocument(document: AnalysisDocument): AnalysisDocument {
  return sanitizeUnknown(document) as AnalysisDocument;
}

function plainText(value: string): string {
  return cleanImportedText(value)
    .replace(/```[\s\S]*?```/g, '')
    .replace(/^\s{0,3}#{1,6}\s*/gm, '')
    .replace(/^\s*[-*+]\s+/gm, '')
    .replace(/^\s*\d+[.)]\s+/gm, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function contentLines(section: AnalysisSectionInput): string[] {
  const visualLines = (section.visual_content_markdown || '')
    .split(/\r?\n/)
    .map((line) => cleanImportedText(line.replace(/^\s*(?:[-*+]\s+|\d+[.)]\s+|#{1,6}\s*)/, '').trim()))
    .filter(Boolean);

  const fallback = plainText(section.raw_ocr_text || '');
  const lines = visualLines.length ? visualLines : fallback ? [fallback] : [];
  return lines.slice(0, 8);
}

function wrapSvgText(value: string, maxLength = 62): string[] {
  const words = value.split(/\s+/).filter(Boolean);
  const lines: string[] = [];
  let current = '';

  words.forEach((word) => {
    if ((current + ' ' + word).trim().length > maxLength && current) {
      lines.push(current);
      current = word;
    } else {
      current = `${current} ${word}`.trim();
    }
  });

  if (current) lines.push(current);
  return lines.slice(0, 9);
}

function makeSectionBoardSvg(section: AnalysisSectionInput, index: number): string {
  const title = textOrFallback(section.title, `Section ${index + 1}`);
  const lines = contentLines(section).flatMap((line) => wrapSvgText(line));
  const visibleLines = lines.length ? lines : ['No visual or OCR content was supplied for this section.'];
  const textMarkup = visibleLines.map((line, lineIndex) => (
    `<text x="48" y="${138 + lineIndex * 30}" fill="#e2e8f0" font-size="18" font-family="sans-serif">${escapeXml(line)}</text>`
  )).join('');

  return `<svg viewBox="0 0 800 500" xmlns="http://www.w3.org/2000/svg">
    <rect width="800" height="500" rx="16" fill="#0f172a"/>
    <rect x="28" y="28" width="744" height="444" rx="12" fill="#172554" stroke="#334155"/>
    <text x="48" y="78" fill="#67e8f9" font-size="24" font-weight="700" font-family="sans-serif">${escapeXml(title)}</text>
    <text x="48" y="108" fill="#94a3b8" font-size="14" font-family="monospace">Imported ${escapeXml(section.kind || 'content')} • Section ${index + 1}</text>
    ${textMarkup}
  </svg>`;
}

function makeListDiagramSvg(title: string, lines: string[], accent: string): string {
  const nodes = (lines.length ? lines : ['Visual content']).slice(0, 5);
  const nodeMarkup = nodes.map((line, index) => {
    const x = 36 + index * 142;
    const label = wrapSvgText(line, 17).slice(0, 2);
    const textMarkup = label.map((text, textIndex) => (
      `<text x="${x + 58}" y="${145 + textIndex * 15}" fill="#e2e8f0" font-size="11" text-anchor="middle" font-family="sans-serif">${escapeXml(text)}</text>`
    )).join('');
    const arrow = index < nodes.length - 1
      ? `<path d="M ${x + 116} 170 L ${x + 140} 170" stroke="${accent}" stroke-width="3" marker-end="url(#arrow)"/>`
      : '';
    return `<rect x="${x}" y="112" width="116" height="116" rx="16" fill="#172554" stroke="${accent}" stroke-width="2"/>${textMarkup}${arrow}`;
  }).join('');

  return `<svg viewBox="0 0 760 280" xmlns="http://www.w3.org/2000/svg">
    <defs><marker id="arrow" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto"><path d="M0,0 L8,4 L0,8 z" fill="${accent}"/></marker></defs>
    <rect width="760" height="280" rx="16" fill="#0f172a"/>
    <text x="36" y="54" fill="${accent}" font-size="20" font-weight="700" font-family="sans-serif">${escapeXml(title)}</text>
    ${nodeMarkup}
  </svg>`;
}

function extractLatexExpressions(value: string): string[] {
  const expressions = [
    ...Array.from(value.matchAll(/\$([^$]+)\$/g), (match) => match[1]),
    ...Array.from(value.matchAll(/\\\(([^)]+)\\\)/g), (match) => match[1]),
    ...Array.from(value.matchAll(/\\\[([\s\S]+?)\\\]/g), (match) => match[1])
  ];

  return Array.from(new Set(expressions.map((expression) => expression.trim()).filter(Boolean)));
}

function createFormulaItems(section: AnalysisSectionInput, sectionIndex: number): FormulaItem[] {
  const source = cleanImportedText([
    section.visual_content_markdown || '',
    section.raw_ocr_text || '',
    section.section_summary || ''
  ].join('\n'));

  return extractLatexExpressions(source).map((latex, formulaIndex) => ({
    id: `formula-${section.id || sectionIndex}-${formulaIndex}`,
    latex,
    description: languageRecord(textOrFallback(section.section_summary, 'Formula extracted from this section.')),
    variableBreakdown: languageRecord({})
  }));
}

function createFormulaItemsFromText(source: string, idPrefix: string): FormulaItem[] {
  return extractLatexExpressions(cleanImportedText(source)).map((latex, formulaIndex) => ({
    id: `formula-${idPrefix}-${formulaIndex}`,
    latex,
    description: languageRecord('Formula extracted from the imported lecture content.'),
    variableBreakdown: languageRecord({})
  }));
}

function sectionDiagram(section: AnalysisSectionInput, sectionIndex: number): DiagramSnippet[] {
  const lines = contentLines(section);
  const visualDescription = cleanImportedText(`${section.visual_content_markdown || ''} ${section.raw_ocr_text || ''}`);
  if (!visualDescription.match(/diagram|flow|chart|graph|process|architecture|table|tree|cycle|pipeline|sequence/i)) {
    return [];
  }

  const title = textOrFallback(section.title, `Section ${sectionIndex + 1}`);
  const explanation = textOrFallback(section.section_summary, plainText(section.visual_content_markdown || section.raw_ocr_text || 'Visual content extracted from this section.'));
  const takeaways = lines.length ? lines.slice(0, 4) : [explanation];
  const type = visualDescription.match(/tree/i)
    ? 'tree'
    : visualDescription.match(/graph|chart/i)
      ? 'graph'
      : visualDescription.match(/flow|process|pipeline|sequence/i)
        ? 'architecture'
        : 'architecture';

  return [{
    id: `diagram-${section.id || sectionIndex}`,
    title,
    type,
    roughSketchSvg: makeListDiagramSvg(title, lines, '#f59e0b'),
    cleanDiagramSvg: makeListDiagramSvg(title, lines, '#22d3ee'),
    explanations: languageRecord(explanation),
    keyTakeaways: languageRecord(takeaways)
  }];
}

function sectionTimestamp(section: AnalysisSectionInput): number | null {
  return section.location?.timestamp_ranges?.[0]?.[0] ?? null;
}

function sectionEndTimestamp(section: AnalysisSectionInput): number | null {
  return section.location?.timestamp_ranges?.[0]?.[1] ?? null;
}

function createPages(document: AnalysisDocument, pptxSlides: PptxSlide[]): WhiteboardPage[] {
  const sourceSections = document.sections?.length
    ? document.sections
    : [{
        id: 'overview',
        kind: 'heading_section',
        title: textOrFallback(document.summary?.one_liner, 'Imported lecture overview'),
        visual_content_markdown: document.summary?.global || '',
        raw_ocr_text: document.summary?.global || '',
        section_summary: document.summary?.one_liner || ''
      } satisfies AnalysisSectionInput];
  const pageCount = Math.max(sourceSections.length, pptxSlides.length, 1);

  const pages = Array.from({ length: pageCount }, (_, index) => {
    const slide = pptxSlides[index];
    const sourceSection = sourceSections[index];
    const section: AnalysisSectionInput = {
      ...(sourceSection || {}),
      id: sourceSection?.id || `ppt-slide-${index + 1}`,
      kind: sourceSection?.kind || 'slide',
      title: textOrFallback(sourceSection?.title, slide?.title || `Slide ${index + 1}`),
      visual_content_markdown: cleanImportedText([sourceSection?.visual_content_markdown, slide?.text].filter(Boolean).join('\n')),
      raw_ocr_text: cleanImportedText([sourceSection?.raw_ocr_text, slide?.text].filter(Boolean).join('\n')),
      section_summary: cleanImportedText(sourceSection?.section_summary || '')
    };
    const title = textOrFallback(section.title, slide?.title || `Slide ${index + 1}`);
    const spoken = (section.spoken_content || []).map((item) => textOrFallback(item.text, '')).filter(Boolean);
    const extractedText = cleanImportedText([section.raw_ocr_text, section.section_summary, ...spoken].filter(Boolean).join('\n\n'));
    const assetPath = section.asset_path?.trim();
    const usableAssetPath = assetPath && (assetPath.startsWith('data:') || assetPath.startsWith('<svg') || assetPath.startsWith('http'))
      ? assetPath
      : undefined;

    return {
      id: section.id || `section-${index + 1}`,
      pageNumber: index + 1,
      title,
      timestamp: formatTimestamp(sectionTimestamp(section)),
      endTimestamp: formatTimestamp(sectionEndTimestamp(section)),
      boardImageSvg: slide?.imageDataUrl || usableAssetPath || makeSectionBoardSvg(section, index),
      handwrittenNotes: contentLines(section),
      extractedText,
      spokenHighlights: (section.spoken_content || [])
        .filter((item) => item.text?.trim())
        .map((item) => ({
          timestamp: formatTimestamp(item.start),
          endTimestamp: formatTimestamp(item.end),
          text: cleanImportedText(item.text!.trim())
        })),
      diagrams: sectionDiagram(section, index),
      formulas: createFormulaItems(section, index)
    };
  });

  const globalFormulaSource = [
    document.summary?.global || '',
    document.summary?.one_liner || '',
    ...(document.summary?.key_concepts || []).map((concept) => `${concept.concept || ''}\n${concept.explanation || ''}`)
  ].join('\n');
  const globalFormulas = createFormulaItemsFromText(globalFormulaSource, 'summary');

  if (globalFormulas.length && pages[0]) {
    pages[0] = {
      ...pages[0],
      formulas: [...pages[0].formulas, ...globalFormulas.filter((formula) => (
        !pages[0].formulas.some((existing) => existing.latex === formula.latex)
      ))]
    };
  }

  return pages;
}

function createTranscript(document: AnalysisDocument, pages: WhiteboardPage[]): TranscriptSegment[] {
  const sections = document.sections || [];
  return (document.transcript || []).filter((item) => item.text?.trim()).map((item, index) => {
    const matchingSectionIndex = sections.findIndex((section) => (
      section.location?.timestamp_ranges?.some(([start, end]) => (
        typeof item.start === 'number' && item.start >= start && item.start <= end
      ))
    ));
    const pageIndex = matchingSectionIndex >= 0 ? matchingSectionIndex : 0;
    const text = item.text!.trim();

    return {
      id: `transcript-${index + 1}`,
      timestamp: formatTimestamp(item.start),
      endTimestamp: formatTimestamp(item.end),
      speaker: 'Speaker',
      originalEnglishText: text,
      translations: languageRecord(text),
      associatedPageId: pages[pageIndex]?.id || pages[0]?.id || ''
    };
  });
}

/**
 * Creates the same internal analysis shape used by JSON imports when the
 * Smartboard flow receives only a PDF. The page images and OCR text are kept
 * as source evidence; Gemini is responsible for turning them into explanations
 * and handwritten-style notes later in the pipeline.
 */
export function buildAnalysisDocumentFromPdfPages(
  pages: PptxSlide[],
  sourceFile: string
): AnalysisDocument {
  const title = stripExtension(sourceFile) || 'Imported PDF lecture';

  return {
    meta: {
      source_file: sourceFile,
      source_type: 'pdf',
      duration_seconds: null,
      page_count: pages.length,
      language: 'en',
      mode: 'ocr',
      processed_at: new Date().toISOString(),
      tool_version: 'pdf-ocr'
    },
    summary: {
      global: `OCR text and rendered page images were extracted from ${title}.`,
      one_liner: title,
      key_concepts: [],
      chapters: []
    },
    sections: pages.map((page, index) => ({
      id: `pdf-page-${page.index || index + 1}`,
      kind: 'page',
      title: page.title || `Page ${index + 1}`,
      location: { timestamp_ranges: null, pages: [page.index || index + 1] },
      visual_content_markdown: page.text || '',
      raw_ocr_text: page.text || '',
      spoken_content: [],
      section_summary: '',
      asset_path: page.imageDataUrl || null
    })),
    transcript: []
  };
}

export function isAnalysisDocument(value: unknown): value is AnalysisDocument {
  if (!value || typeof value !== 'object') return false;
  const candidate = value as AnalysisDocument;
  return Boolean(candidate.summary || candidate.sections || candidate.meta);
}

export function buildLectureFromAnalysis(
  document: AnalysisDocument,
  _targetLang: TargetLanguage = 'en',
  pptxSlides: PptxSlide[] = []
): Lecture {
  const cleanDocument = sanitizeAnalysisDocument(document);
  const meta = cleanDocument.meta || {};
  const sourceFile = textOrFallback(meta.source_file, 'Imported lecture');
  const pages = createPages(cleanDocument, pptxSlides);
  const chapters: LectureChapter[] = (cleanDocument.summary?.chapters || []).map((chapter) => ({
    title: textOrFallback(chapter.title, 'Untitled chapter'),
    timestamp: chapter.start?.timestamp ?? undefined,
    page: chapter.start?.page ?? undefined
  }));

  const keyConcepts = (cleanDocument.summary?.key_concepts || []).filter((concept) => concept.concept?.trim()).map((concept) => ({
    concept: cleanImportedText(concept.concept!.trim()),
    explanation: textOrFallback(concept.explanation, 'No explanation was supplied.')
  }));

  const globalSummary = textOrFallback(cleanDocument.summary?.global, 'No global summary was supplied.');
  const oneLiner = textOrFallback(cleanDocument.summary?.one_liner, stripExtension(sourceFile));
  const technicalTerms = keyConcepts.map((concept) => ({
    term: concept.concept,
    definition: concept.explanation
  }));
  const processedDate = formatProcessedDate(meta.processed_at);
  const sourceMeta: LectureSourceMeta = {
    sourceFile,
    sourceType: textOrFallback(meta.source_type, 'unknown'),
    durationSeconds: meta.duration_seconds ?? null,
    pageCount: meta.page_count ?? pages.length,
    language: meta.language,
    mode: meta.mode,
    processedAt: meta.processed_at,
    toolVersion: meta.tool_version
  };

  return {
    id: `analysis-${Date.now()}`,
    title: oneLiner,
    subject: stripExtension(sourceFile),
    instructor: '',
    date: processedDate,
    duration: formatDuration(meta.duration_seconds),
    pages,
    transcript: createTranscript(cleanDocument, pages),
    chapters,
    oneLiner,
    globalSummary,
    sourceMeta,
    notes: {
      title: languageRecord(oneLiner),
      lectureOverview: languageRecord(globalSummary),
      keyConcepts: languageRecord(keyConcepts),
      simplifiedSummary: languageRecord(oneLiner),
      technicalTerms: languageRecord(technicalTerms)
    }
  };
}
