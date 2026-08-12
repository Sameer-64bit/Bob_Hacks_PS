// Built-in languages remain strongly identified by their familiar codes, but
// custom languages use a `custom:<encoded name>` key so Gemini can translate
// into any language without changing the persisted data shape.
export type TargetLanguage = string;

export type BuiltInTargetLanguage = 'en' | 'hi' | 'bn' | 'ar';

export interface LanguageInfo {
  code: TargetLanguage;
  name: string;
  nativeName: string;
  flag: string;
  dir: 'ltr' | 'rtl';
  fontFamily: string;
}

export const SUPPORTED_LANGUAGES: Record<BuiltInTargetLanguage, LanguageInfo> = {
  en: {
    code: 'en',
    name: 'English',
    nativeName: 'English',
    flag: '🇬🇧',
    dir: 'ltr',
    fontFamily: "'Inter', sans-serif"
  },
  hi: {
    code: 'hi',
    name: 'Hindi',
    nativeName: 'हिंदी',
    flag: '🇮🇳',
    dir: 'ltr',
    fontFamily: "'Noto Sans Devanagari', 'Inter', sans-serif"
  },
  bn: {
    code: 'bn',
    name: 'Bangla',
    nativeName: 'বাংলা',
    flag: '🇧🇩',
    dir: 'ltr',
    fontFamily: "'Noto Sans Bengali', 'Inter', sans-serif"
  },
  ar: {
    code: 'ar',
    name: 'Arabic',
    nativeName: 'العربية',
    flag: '🇸🇦',
    dir: 'rtl',
    fontFamily: "'Amiri', 'Inter', sans-serif"
  }
};

function titleCaseLanguage(value: string): string {
  return value
    .replace(/[-_]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/\b\w/g, (character) => character.toUpperCase());
}

function decodeCustomLanguage(code: string): string | undefined {
  if (!code.startsWith('custom:')) return undefined;
  try {
    const decoded = decodeURIComponent(code.slice('custom:'.length)).trim();
    return decoded || undefined;
  } catch {
    return code.slice('custom:'.length).trim() || undefined;
  }
}

export function createCustomLanguage(label: string): LanguageInfo | null {
  const normalized = label.trim().replace(/\s+/g, ' ');
  if (!normalized) return null;

  const isRtl = /[\u0590-\u08ff]/.test(normalized)
    || /\b(arabic|urdu|persian|farsi|hebrew|right[- ]to[- ]left)\b/i.test(normalized);

  return {
    code: `custom:${encodeURIComponent(normalized)}`,
    name: normalized,
    nativeName: normalized,
    flag: '🌐',
    dir: isRtl ? 'rtl' : 'ltr',
    fontFamily: isRtl ? "'Amiri', 'Inter', sans-serif" : "'Inter', sans-serif"
  };
}

export function getLanguageInfo(language: TargetLanguage): LanguageInfo {
  const builtIn = SUPPORTED_LANGUAGES[language as BuiltInTargetLanguage];
  if (builtIn) return builtIn;

  const customName = decodeCustomLanguage(language) || titleCaseLanguage(language);
  const custom = createCustomLanguage(customName);
  return custom || {
    code: language,
    name: language || 'Unknown language',
    nativeName: language || 'Unknown language',
    flag: '🌐',
    dir: 'ltr',
    fontFamily: "'Inter', sans-serif"
  };
}

export interface DiagramSnippet {
  id: string;
  title: string;
  roughSketchSvg: string; // Original teacher's rough board sketch
  cleanDiagramSvg: string; // AI cleaned-up vector / chart representation
  type: 'graph' | 'tree' | 'chart' | 'circuit' | 'architecture';
  explanations: Record<TargetLanguage, string>;
  keyTakeaways: Record<TargetLanguage, string[]>;
}

export interface FormulaItem {
  id: string;
  latex: string;
  description: Record<TargetLanguage, string>;
  variableBreakdown: Record<TargetLanguage, Record<string, string>>;
}

export interface WhiteboardPage {
  id: string;
  pageNumber: number;
  title: string;
  timestamp: string; // e.g. "04:15"
  endTimestamp?: string;
  boardImageSvg: string; // Full smartboard slide SVG representation
  handwrittenNotes: string[];
  extractedText: string;
  spokenHighlights?: Array<{
    timestamp: string;
    endTimestamp?: string;
    text: string;
  }>;
  diagrams: DiagramSnippet[];
  formulas: FormulaItem[];
  localized?: Partial<Record<TargetLanguage, {
    title?: string;
    extractedText?: string;
    handwrittenNotes?: string[];
    spokenHighlights?: Array<{
      timestamp: string;
      endTimestamp?: string;
      text: string;
    }>;
  }>>;
}

export interface TranscriptSegment {
  id: string;
  timestamp: string;
  endTimestamp?: string;
  speaker: string;
  originalEnglishText: string;
  translations: Record<TargetLanguage, string>;
  associatedPageId: string;
}

export type AiNoteSectionKind =
  | 'overview'
  | 'definition'
  | 'comparison'
  | 'process'
  | 'formula'
  | 'example'
  | 'checklist'
  | 'diagram'
  | 'summary'
  | 'custom';

export interface AiNoteSection {
  id: string;
  title: string;
  kind: AiNoteSectionKind;
  body: string;
  bullets: string[];
  formula?: string;
  diagramDescription?: string;
}

export interface StructuredNotes {
  title: Record<TargetLanguage, string>;
  lectureOverview: Record<TargetLanguage, string>;
  keyConcepts: Record<TargetLanguage, Array<{ concept: string; explanation: string }>>;
  simplifiedSummary: Record<TargetLanguage, string>;
  technicalTerms: Record<TargetLanguage, Array<{ term: string; definition: string }>>;
  generatedSections?: Partial<Record<TargetLanguage, AiNoteSection[]>>;
}

export interface LectureChapter {
  title: string;
  timestamp?: number;
  page?: number;
}

export interface LectureSourceMeta {
  sourceFile: string;
  sourceType: 'video' | 'pdf' | string;
  durationSeconds?: number | null;
  pageCount?: number | null;
  language?: string;
  mode?: string;
  processedAt?: string;
  toolVersion?: string;
}

export interface Lecture {
  id: string;
  title: string;
  subject: string;
  instructor: string;
  date: string;
  duration: string;
  pages: WhiteboardPage[];
  transcript: TranscriptSegment[];
  notes: StructuredNotes;
  chapters?: LectureChapter[];
  oneLiner?: string;
  globalSummary?: string;
  sourceMeta?: LectureSourceMeta;
  generation?: {
    aiGenerated: boolean;
    generatedLanguages: TargetLanguage[];
    message?: string;
  };
}

export interface QAMessage {
  id: string;
  sender: 'user' | 'ai';
  text: string;
  language: TargetLanguage;
  timestamp: string;
  referencedPageId?: string;
  referencedDiagramId?: string;
}
