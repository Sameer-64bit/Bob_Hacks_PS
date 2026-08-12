import type { AiNoteSection, Lecture, StructuredNotes, TargetLanguage } from '../types';
import { getLanguageInfo } from '../types';
import {
  buildAnalysisDocumentFromPdfPages,
  buildLectureFromAnalysis,
  sanitizeAnalysisDocument,
  type AnalysisDocument,
  type AnalysisSectionInput
} from './analysisDocument';
import { extractPptxSlides, type PptxSlide } from './pptxParser';
import { extractPdfPages } from './pdfParser';

interface GeneratedConcept {
  concept?: string;
  explanation?: string;
}

interface GeneratedTerm {
  term?: string;
  definition?: string;
}

interface GeneratedSection {
  id?: string;
  title?: string;
  summary?: string;
  handwritten_notes?: string[];
  diagram_explanation?: string;
  diagram_key_takeaways?: string[];
}

interface GeneratedNoteSection {
  id?: string;
  title?: string;
  kind?: string;
  body?: string;
  bullets?: string[];
  formula?: string;
  diagram_description?: string;
}

interface GeneratedTranscript {
  id?: string;
  text?: string;
}

export interface GeneratedNotesPayload {
  language?: string;
  title?: string;
  lecture_overview?: string;
  simplified_summary?: string;
  key_concepts?: GeneratedConcept[];
  technical_terms?: GeneratedTerm[];
  note_sections?: GeneratedNoteSection[];
  sections?: GeneratedSection[];
  transcript?: GeneratedTranscript[];
}

export interface NotesPipelineResult {
  lecture: Lecture;
  presentationPages: PptxSlide[];
  aiGenerated: boolean;
  message?: string;
}

function configuredEndpoint(): string {
  return (import.meta.env.VITE_AI_NOTES_ENDPOINT || '').trim();
}

function nonEmptyString(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim() ? value.trim() : undefined;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === 'object' && !Array.isArray(value);
}

function unwrapPayload(value: unknown): GeneratedNotesPayload {
  if (!isRecord(value)) throw new Error('The AI notes response must be a JSON object.');
  const candidate = isRecord(value.notes) ? value.notes : value;
  return candidate as GeneratedNotesPayload;
}

function withLanguage<T>(record: Record<TargetLanguage, T>, language: TargetLanguage, value: T): Record<TargetLanguage, T> {
  return { ...record, [language]: value };
}

function mergeGeneratedNotes(
  lecture: Lecture,
  payload: GeneratedNotesPayload,
  targetLang: TargetLanguage,
  updateLectureMetadata = true
): Lecture {
  const generatedTitle = nonEmptyString(payload.title);
  const generatedOverview = nonEmptyString(payload.lecture_overview);
  const generatedSummary = nonEmptyString(payload.simplified_summary);
  const generatedConcepts = Array.isArray(payload.key_concepts)
    ? payload.key_concepts
      .map((item) => ({
        concept: nonEmptyString(item.concept),
        explanation: nonEmptyString(item.explanation)
      }))
      .filter((item): item is { concept: string; explanation: string } => Boolean(item.concept && item.explanation))
    : undefined;
  const generatedTerms = Array.isArray(payload.technical_terms)
    ? payload.technical_terms
      .map((item) => ({ term: nonEmptyString(item.term), definition: nonEmptyString(item.definition) }))
      .filter((item): item is { term: string; definition: string } => Boolean(item.term && item.definition))
    : undefined;
  const generatedNoteSections: AiNoteSection[] | undefined = Array.isArray(payload.note_sections)
    ? payload.note_sections.map((item, index) => {
      const validKinds = ['overview', 'definition', 'comparison', 'process', 'formula', 'example', 'checklist', 'diagram', 'summary', 'custom'] as const;
      const kind = validKinds.includes(item.kind as typeof validKinds[number])
        ? item.kind as AiNoteSection['kind']
        : 'custom';
      return {
        id: nonEmptyString(item.id) || `ai-note-${index + 1}`,
        title: nonEmptyString(item.title) || `Study note ${index + 1}`,
        kind,
        body: nonEmptyString(item.body) || '',
        bullets: Array.isArray(item.bullets)
          ? item.bullets.filter((bullet): bullet is string => typeof bullet === 'string' && Boolean(bullet.trim()))
          : [],
        formula: nonEmptyString(item.formula),
        diagramDescription: nonEmptyString(item.diagram_description)
      } satisfies AiNoteSection;
    })
    : undefined;

  const notes: StructuredNotes = {
    ...lecture.notes,
    title: generatedTitle ? withLanguage(lecture.notes.title, targetLang, generatedTitle) : lecture.notes.title,
    lectureOverview: generatedOverview
      ? withLanguage(lecture.notes.lectureOverview, targetLang, generatedOverview)
      : lecture.notes.lectureOverview,
    simplifiedSummary: generatedSummary
      ? withLanguage(lecture.notes.simplifiedSummary, targetLang, generatedSummary)
      : lecture.notes.simplifiedSummary,
    keyConcepts: generatedConcepts
      ? withLanguage(lecture.notes.keyConcepts, targetLang, generatedConcepts)
      : lecture.notes.keyConcepts,
    technicalTerms: generatedTerms
      ? withLanguage(lecture.notes.technicalTerms, targetLang, generatedTerms)
      : lecture.notes.technicalTerms,
    generatedSections: generatedNoteSections
      ? { ...lecture.notes.generatedSections, [targetLang]: generatedNoteSections }
      : lecture.notes.generatedSections
  };

  const generatedSections = Array.isArray(payload.sections) ? payload.sections : [];
  const pages = lecture.pages.map((page, index) => {
    const generated = generatedSections.find((item) => item.id === page.id) || generatedSections[index];
    if (!generated) return page;

    // Once Gemini has answered, never fall back to raw OCR for this AI-only
    // surface. Missing output should be visible as missing AI output rather
    // than being presented as an AI explanation.
    const handwrittenNotes = Array.isArray(generated.handwritten_notes)
      ? generated.handwritten_notes.filter((note): note is string => typeof note === 'string' && Boolean(note.trim()))
      : [];
    const summary = nonEmptyString(generated.summary);
    const diagramExplanation = nonEmptyString(generated.diagram_explanation);
    const diagramTakeaways = Array.isArray(generated.diagram_key_takeaways)
      ? generated.diagram_key_takeaways.filter((takeaway): takeaway is string => typeof takeaway === 'string' && Boolean(takeaway.trim()))
      : [];
    const diagrams = page.diagrams.map((diagram) => ({
      ...diagram,
      explanations: diagramExplanation
        ? { ...diagram.explanations, [targetLang]: diagramExplanation }
        : diagram.explanations,
      keyTakeaways: diagramTakeaways.length
        ? { ...diagram.keyTakeaways, [targetLang]: diagramTakeaways }
        : diagram.keyTakeaways
    }));

    const localizedPage = page.localized?.[targetLang] || {};

    return {
      ...page,
      localized: {
        ...page.localized,
        [targetLang]: {
          ...localizedPage,
          title: nonEmptyString(generated.title) || localizedPage.title || page.title,
          handwrittenNotes,
          extractedText: summary || localizedPage.extractedText || ''
        }
      },
      diagrams
    };
  });

  const transcript = lecture.transcript.map((segment, index) => {
    const generated = payload.transcript?.find((item) => item.id === segment.id) || payload.transcript?.[index];
    const translatedText = nonEmptyString(generated?.text);
    return translatedText
      ? { ...segment, translations: withLanguage(segment.translations, targetLang, translatedText) }
      : segment;
  });

  return {
    ...lecture,
    ...(updateLectureMetadata
      ? {
        title: generatedTitle || lecture.title,
        oneLiner: generatedSummary || generatedTitle || lecture.oneLiner,
        globalSummary: generatedOverview || lecture.globalSummary
      }
      : {}),
    notes,
    pages,
    transcript
  };
}

async function generateWithAI(
  document: AnalysisDocument,
  presentationPages: PptxSlide[],
  targetLang: TargetLanguage
): Promise<GeneratedNotesPayload | null> {
  const endpoint = configuredEndpoint();
  if (!endpoint) return null;

  const language = getLanguageInfo(targetLang);
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      target_language: targetLang,
      target_language_name: language.name,
      preserve_latex: true,
      input: sanitizeAnalysisDocument(document),
      presentation_pages: presentationPages.map((slide) => ({
        index: slide.index,
        title: slide.title,
        text: slide.text,
        // Text-rich PDF pages do not need a second, very large base64 image in
        // the Gemini request. Keep images for scanned/mostly visual pages so
        // OCR and vision still work without making normal PDF uploads exceed
        // the request-size limit.
        image_data_url: slide.text.trim().length < 240 ? slide.imageDataUrl : undefined
      })),
      instructions: [
        'Generate concise, student-friendly handwritten-style study notes from only the supplied lecture input.',
        'Do not use a fixed subject, example, professor, chapter, or formula.',
        'Use the requested language for every generated field.',
        'Preserve mathematical notation exactly in LaTeX delimiters such as $...$ or $$...$$.',
        'Return JSON only using the documented fields: title, lecture_overview, simplified_summary, key_concepts, technical_terms, note_sections, sections, transcript.',
        'note_sections must be generated from the lecture. Choose the useful section kind for the topic; do not force a fixed order or fixed BST-style template.',
        'For every item in sections, write summary as a short explanation of what that slide means and why it matters to a student. Write handwritten_notes as 3 to 6 concise analytical takeaways derived from the slide; explain relationships, purpose, cause/effect or practical meaning instead of repeating headings or copying OCR lines.',
        'Do not copy slide text line-by-line into handwritten_notes. Do not return raw OCR, UI labels, repeated punctuation, star/rating annotations, or meaningless fragments. If a slide is mostly a list, group the list into meaningful categories and explain the overall idea.',
        'Every handwritten_notes item must be a complete, understandable explanatory sentence. Do not start notes with words such as covers, lists, topics, slide, or figure; explain the underlying concept directly.',
        'Return exactly one sections item for every input analysis_json.sections item, preserve each source section id exactly, and do not omit slides. The sections array is the source for the Whiteboard AI Slide Analysis panel.',
        'For diagrams, provide diagram_description only when the source supports a visual explanation. Do not invent unsupported facts.',
        'For every slide section, return diagram_explanation and diagram_key_takeaways as an empty string and empty array when no diagram is present; otherwise translate and explain the diagram in the requested language.'
      ]
    })
  });

  const responseText = await response.text();
  let responseBody: unknown;
  try {
    responseBody = JSON.parse(responseText);
  } catch {
    responseBody = null;
  }

  if (!response.ok) {
    const serviceError = isRecord(responseBody) ? nonEmptyString(responseBody.error) : undefined;
    throw new Error(serviceError || `AI notes service returned HTTP ${response.status}.`);
  }

  return unwrapPayload(responseBody);
}

function timestampToSeconds(value?: string): number | undefined {
  if (!value || value === '—') return undefined;
  const parts = value.split(':').map(Number);
  if (parts.some((part) => !Number.isFinite(part))) return undefined;
  if (parts.length === 2) return parts[0] * 60 + parts[1];
  if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
  return undefined;
}

function lectureToAnalysisDocument(lecture: Lecture): AnalysisDocument {
  const sections: AnalysisSectionInput[] = lecture.pages.map((page) => {
    const start = timestampToSeconds(page.timestamp);
    const end = timestampToSeconds(page.endTimestamp);
    const spokenContent = (page.spokenHighlights || []).map((highlight) => ({
      start: timestampToSeconds(highlight.timestamp),
      end: timestampToSeconds(highlight.endTimestamp),
      text: highlight.text
    }));

    return {
      id: page.id,
      kind: 'slide',
      title: page.title,
      location: {
        timestamp_ranges: typeof start === 'number'
          ? [[start, typeof end === 'number' ? end : start]]
          : null,
        pages: [page.pageNumber]
      },
      visual_content_markdown: page.extractedText,
      raw_ocr_text: page.extractedText,
      spoken_content: spokenContent,
      section_summary: page.localized?.en?.extractedText || page.extractedText,
      asset_path: page.boardImageSvg.startsWith('data:image/') ? page.boardImageSvg : null
    };
  });

  return {
    meta: {
      source_file: lecture.sourceMeta?.sourceFile || lecture.title,
      source_type: lecture.sourceMeta?.sourceType || 'lecture',
      page_count: lecture.pages.length,
      language: lecture.sourceMeta?.language || 'en',
      mode: 'on-demand-translation',
      processed_at: lecture.sourceMeta?.processedAt,
      tool_version: lecture.sourceMeta?.toolVersion
    },
    summary: {
      global: lecture.globalSummary || lecture.notes.lectureOverview.en || lecture.title,
      one_liner: lecture.oneLiner || lecture.title,
      key_concepts: lecture.notes.keyConcepts.en,
      chapters: (lecture.chapters || []).map((chapter) => ({
        title: chapter.title,
        start: { timestamp: chapter.timestamp ?? null, page: chapter.page ?? null }
      }))
    },
    sections,
    transcript: lecture.transcript.map((segment) => ({
      start: timestampToSeconds(segment.timestamp),
      end: timestampToSeconds(segment.endTimestamp),
      text: segment.originalEnglishText
    }))
  };
}

function lectureToPresentationPages(lecture: Lecture): PptxSlide[] {
  return lecture.pages.map((page) => ({
    index: page.pageNumber,
    title: page.title,
    text: page.extractedText,
    imageDataUrl: page.boardImageSvg.startsWith('data:image/') ? page.boardImageSvg : undefined
  }));
}

async function generateLectureWithExtractedPages(
  document: AnalysisDocument,
  targetLang: TargetLanguage,
  presentationPages: PptxSlide[]
): Promise<NotesPipelineResult> {
  const baseLecture = buildLectureFromAnalysis(document, targetLang, presentationPages);
  const language = getLanguageInfo(targetLang);

  try {
    const generatedPayload = await generateWithAI(document, presentationPages, targetLang);
    if (!generatedPayload) {
      return {
        lecture: {
          ...baseLecture,
          generation: {
            aiGenerated: false,
            generatedLanguages: [],
            message: 'Source-derived notes are shown because no AI endpoint is configured.'
          }
        },
        presentationPages,
        aiGenerated: false,
        message: 'JSON and presentation imported. Configure VITE_AI_NOTES_ENDPOINT to enable AI-written notes.'
      };
    }

    return {
      lecture: {
        ...mergeGeneratedNotes(baseLecture, generatedPayload, targetLang),
        generation: {
          aiGenerated: true,
          generatedLanguages: [targetLang],
            message: `AI notes generated in ${language.name}.`
        }
      },
      presentationPages,
      aiGenerated: true,
      message: `AI notes generated in ${language.name}.`
    };
  } catch (error) {
    return {
      lecture: {
        ...baseLecture,
        generation: {
          aiGenerated: false,
          generatedLanguages: [],
          message: error instanceof Error ? error.message : 'AI notes generation failed.'
        }
      },
      presentationPages,
      aiGenerated: false,
      message: error instanceof Error
        ? `${error.message} JSON/presentation content was still imported without generated prose.`
        : 'AI notes generation failed. JSON/presentation content was still imported.'
    };
  }
}

export async function generateLectureFromInputs(
  document: AnalysisDocument,
  targetLang: TargetLanguage,
  presentationFile?: File | null
): Promise<NotesPipelineResult> {
  const presentationPages = presentationFile
    ? presentationFile.name.toLowerCase().endsWith('.pdf')
      ? await extractPdfPages(presentationFile)
      : await extractPptxSlides(presentationFile)
    : [];

  return generateLectureWithExtractedPages(document, targetLang, presentationPages);
}

/**
 * PDF-only Smartboard ingestion. It creates an analysis document from OCR and
 * rendered pages, then uses the same Gemini notes pipeline as JSON imports.
 */
export async function generateLectureFromPdf(
  presentationFile: File,
  targetLang: TargetLanguage,
  onProgress?: (message: string) => void
): Promise<NotesPipelineResult> {
  const presentationPages = await extractPdfPages(presentationFile, {
    runOcr: true,
    onProgress
  });
  onProgress?.('OCR complete. Sending page content to Gemini for AI notes...');

  const document = buildAnalysisDocumentFromPdfPages(presentationPages, presentationFile.name);
  return generateLectureWithExtractedPages(document, targetLang, presentationPages);
}

/**
 * Translates an already loaded lecture without re-uploading its source files.
 * The original lecture remains intact while the requested language is added
 * to its localized notes, slide content, diagrams and transcript.
 */
export async function translateLectureWithAI(
  lecture: Lecture,
  targetLang: TargetLanguage
): Promise<Lecture> {
  const payload = await generateWithAI(
    lectureToAnalysisDocument(lecture),
    lectureToPresentationPages(lecture),
    targetLang
  );

  if (!payload) {
    throw new Error('AI translation is unavailable because VITE_AI_NOTES_ENDPOINT is not configured.');
  }

  const translatedLecture = mergeGeneratedNotes(lecture, payload, targetLang, false);
  const generatedLanguages = Array.from(new Set([
    ...(lecture.generation?.generatedLanguages || []),
    targetLang
  ]));
  const language = getLanguageInfo(targetLang);

  return {
    ...translatedLecture,
    generation: {
      aiGenerated: true,
      generatedLanguages,
      message: `AI translation generated in ${language.name}.`
    }
  };
}
