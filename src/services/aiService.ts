import type { TargetLanguage, Lecture, WhiteboardPage, QAMessage } from '../types';
import { getLanguageInfo } from '../types';

function languageRecord<T>(value: T): Record<TargetLanguage, T> {
  return {
    en: value,
    hi: value,
    bn: value,
    ar: value
  };
}

function escapeXml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function extractLatexExpressions(value: string): string[] {
  return Array.from(value.matchAll(/\$([^$]+)\$/g), (match) => match[1].trim())
    .filter(Boolean);
}

/**
 * Temporary non-JSON ingestion path. It deliberately uses only the uploaded
 * content. The production lecture workflow is generateLectureFromInputs(),
 * which combines the PPTX and analysis JSON and can call the AI endpoint.
 */
export async function processNewBoardImageAndTranscript(
  boardImageBase64OrSvg: string,
  rawTranscript: string,
  targetLang: TargetLanguage
): Promise<{ page: WhiteboardPage; generatedNotes: string }> {
  await new Promise((resolve) => setTimeout(resolve, 1500));
  const sourceText = rawTranscript.trim();
  const lines = sourceText
    .split(/\r?\n|(?<=[.!?])\s+/)
    .map((line) => line.trim())
    .filter(Boolean);
  const title = lines[0]?.slice(0, 80) || 'Uploaded lecture page';
  const visibleLines = (lines.length ? lines : ['No transcript text supplied.']).slice(0, 8);
  const formulas = extractLatexExpressions(sourceText);

  const boardContent = boardImageBase64OrSvg.startsWith('<svg')
    ? boardImageBase64OrSvg
    : `<svg viewBox="0 0 800 500" width="100%" height="100%" xmlns="http://www.w3.org/2000/svg">
        <rect width="800" height="500" fill="#0f172a" rx="12"/>
        <text x="30" y="50" fill="#38bdf8" font-size="20" font-family="sans-serif">${escapeXml(title)}</text>
        <rect x="40" y="80" width="720" height="380" fill="#1e293b" rx="8" stroke="#334155"/>
        ${visibleLines.map((line, index) => `<text x="60" y="${125 + index * 34}" fill="#cbd5e1" font-size="16" font-family="sans-serif">${escapeXml(line.slice(0, 86))}</text>`).join('')}
      </svg>`;

  const page: WhiteboardPage = {
    id: `page-custom-${Date.now()}`,
    pageNumber: 1,
    title,
    timestamp: '—',
    boardImageSvg: boardContent,
    handwrittenNotes: visibleLines,
    extractedText: sourceText,
    diagrams: [],
    formulas: formulas.map((latex, index) => ({
      id: `form-custom-${Date.now()}-${index}`,
      latex,
      description: languageRecord('Formula extracted from the uploaded lecture content.'),
      variableBreakdown: languageRecord({})
    }))
  };

  return {
    page,
    generatedNotes: `Uploaded content prepared for ${getLanguageInfo(targetLang).name}.`
  };
}

function firstLectureConcept(lecture: Lecture, targetLang: TargetLanguage): string {
  return lecture.notes.keyConcepts[targetLang]?.[0]?.concept
    || lecture.pages[0]?.title
    || lecture.title
    || 'the uploaded lecture';
}

function lectureContext(lecture: Lecture) {
  return {
    title: lecture.title,
    subject: lecture.subject,
    summary: lecture.globalSummary || lecture.notes.lectureOverview.en,
    pages: lecture.pages.map((page) => ({
      number: page.pageNumber,
      title: page.title,
      timestamp: page.timestamp,
      text: page.extractedText,
      notes: page.handwrittenNotes,
      formulas: page.formulas.map((formula) => formula.latex)
    })),
    transcript: lecture.transcript.map((segment) => ({
      timestamp: segment.timestamp,
      text: segment.originalEnglishText
    }))
  };
}

export async function askLectureAI(
  userQuery: string,
  targetLang: TargetLanguage,
  lecture: Lecture,
  history: QAMessage[]
): Promise<QAMessage> {
  const endpoint = (import.meta.env.VITE_AI_QA_ENDPOINT || import.meta.env.VITE_AI_NOTES_ENDPOINT || '').trim();
  let replyText: string;

  if (endpoint) {
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        mode: 'qa',
        target_language: targetLang,
        target_language_name: getLanguageInfo(targetLang).name,
        query: userQuery,
        history: history.slice(-8),
        lecture: lectureContext(lecture)
      })
    });

    if (!response.ok) throw new Error(`AI tutor service returned HTTP ${response.status}.`);
    const payload = await response.json() as { answer?: unknown; text?: unknown };
    replyText = typeof payload.answer === 'string' ? payload.answer : typeof payload.text === 'string' ? payload.text : '';
    if (!replyText.trim()) throw new Error('AI tutor returned no answer.');
  } else {
    const concept = firstLectureConcept(lecture, targetLang);
    const languageName = getLanguageInfo(targetLang).name;
    replyText = targetLang === 'hi'
      ? `यह प्रश्न “${concept}” से संबंधित है। JSON और PPTX पर आधारित विस्तृत उत्तर के लिए AI नोट्स सेवा कनेक्ट करें।`
      : targetLang === 'bn'
        ? `এই প্রশ্নটি “${concept}”-এর সঙ্গে সম্পর্কিত। JSON ও PPTX-ভিত্তিক বিস্তারিত উত্তরের জন্য AI নোটস পরিষেবা সংযুক্ত করুন।`
        : targetLang === 'ar'
          ? `يرتبط هذا السؤال بموضوع «${concept}». للحصول على إجابة تفصيلية مبنية على JSON وPPTX، اربط خدمة ملاحظات الذكاء الاصطناعي.`
          : `This question relates to “${concept}”. Connect the AI notes service for a detailed answer in ${languageName}, grounded in the uploaded JSON and PPTX.`;
  }

  return {
    id: `msg-ai-${Date.now()}`,
    sender: 'ai',
    text: replyText,
    language: targetLang,
    timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
  };
}
