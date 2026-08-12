import React, { useEffect, useRef } from 'react';
import type { Lecture, TargetLanguage } from '../types';
import { getLanguageInfo } from '../types';
import { BookOpen, Star, Lightbulb, CheckCircle2, Code2, Smile } from 'lucide-react';
import { ChapterFlowchart } from './ChapterFlowchart';
import { RichText } from './RichText';
import { AiGeneratedNotes } from './AiGeneratedNotes';
import katex from 'katex';
import 'katex/dist/katex.min.css';

interface MultilingualNotesViewProps {
  lecture: Lecture;
  targetLang: TargetLanguage;
  activePageId: string;
}

export const MultilingualNotesView: React.FC<MultilingualNotesViewProps> = ({
  lecture,
  targetLang,
  activePageId
}) => {
  const notesContainerRef = useRef<HTMLDivElement>(null);
  const langInfo = getLanguageInfo(targetLang);
  const { notes, pages } = lecture;

  const activePage = pages.find((p) => p.id === activePageId) || pages[0];

  const titleText = notes.title[targetLang] || notes.title.en;
  const overviewText = notes.lectureOverview[targetLang] || notes.lectureOverview.en;
  const simplifiedText = notes.simplifiedSummary[targetLang] || notes.simplifiedSummary.en;
  const conceptsList = notes.keyConcepts[targetLang] || notes.keyConcepts.en;
  const techTermsList = notes.technicalTerms[targetLang] || notes.technicalTerms.en;
  const aiGeneratedSections = notes.generatedSections?.[targetLang] || [];
  const hasAiGeneratedNotes = aiGeneratedSections.length > 0;
  const aiHasFormula = aiGeneratedSections.some((section) => section.kind === 'formula' || Boolean(section.formula));

  useEffect(() => {
    if (activePage && activePage.formulas) {
      activePage.formulas.forEach((form) => {
        const el = document.getElementById(`katex-${form.id}`);
        if (el) {
          try {
            katex.render(form.latex, el, {
              throwOnError: false,
              displayMode: true
            });
          } catch (e) {
            console.error('KaTeX render error:', e);
          }
        }
      });
    }
  }, [activePage, targetLang]);

  return (
    <div className="notes-view-shell w-full flex justify-center py-2 px-2">
      <div
        id="printable-notes-container"
        ref={notesContainerRef}
        dir={langInfo.dir}
        className="notes-sheet notebook-paper p-6 sm:p-8 relative overflow-hidden transition-all text-slate-900 w-full max-w-4xl mx-auto shadow-xl"
        style={{ fontFamily: langInfo.fontFamily }}
      >
        {/* Main Content inside Centered Notebook Sheet */}
        <div className="notes-sheet-content space-y-6 relative z-10">

          {lecture.generation && !lecture.generation.generatedLanguages.includes(targetLang) && lecture.sourceMeta?.language !== targetLang && (
            <div className="notes-source-language-banner">
              <strong>Source language content shown</strong>
              <span>AI translation for {langInfo.nativeName} is not available yet. Connect the configured AI notes endpoint and import the lecture again to generate it from this JSON + PPTX.</span>
            </div>
          )}
          
          {/* Notebook Sheet Top Header Banner */}
          <div className="notes-sheet-header border-b-2 border-slate-800 pb-3 flex flex-wrap items-center justify-between gap-4">
            
            <div className="notes-title-block text-center flex-1">
              <h1 className="text-xl sm:text-2xl font-bold font-handwriting tracking-wide text-slate-900 uppercase">
                ✨ CLASSROOM HANDBOOK & AI NOTES ✨
              </h1>
              <div className="w-48 h-0.5 bg-slate-800 my-1 mx-auto sm:mx-0"></div>
              <h2 className="text-sm sm:text-base font-bold font-handwriting text-rose-700">
                {lecture.subject}: {titleText}
              </h2>
              {lecture.generation && (
                <span className={`notes-generation-badge ${lecture.generation.aiGenerated ? 'notes-generation-ai' : 'notes-generation-source'}`}>
                  {lecture.generation.aiGenerated ? '✦ AI-generated content' : 'Source-derived fallback'}
                </span>
              )}
            </div>

            {/* Chapter & Page Number Stamp Badge */}
            <div className="border-2 border-dashed border-indigo-600 rounded-xl px-3 py-1.5 bg-indigo-50/80 text-center font-handwriting shrink-0 shadow-sm">
              <span className="text-xs font-bold text-indigo-900 block">CHAPTER - {activePage.pageNumber}</span>
              <span className="text-[11px] font-bold text-rose-600">Page - {activePage.pageNumber}/{pages.length}</span>
            </div>

          </div>

          {hasAiGeneratedNotes && (
            <AiGeneratedNotes sections={aiGeneratedSections} targetLang={targetLang} />
          )}

          {/* 1. Core Concept Overview */}
          {!hasAiGeneratedNotes && <div className="notes-section space-y-2">
            <div className="notes-section-heading flex items-center gap-2">
              <span className="w-2.5 h-2.5 rounded-full bg-rose-600"></span>
              <h3 className="text-base sm:text-lg font-bold font-handwriting text-rose-900 border-b border-rose-200 inline-block">
                1. {targetLang === 'hi' ? 'व्याख्यान अवलोकन और सिद्धांत' : targetLang === 'bn' ? 'লেকচার ও মূল তত্ত্ব' : targetLang === 'ar' ? 'نظرة عامة على المحاضرة' : 'Lecture Overview & Foundational Principles'}
              </h3>
            </div>

            <div className="notes-overview-grid grid grid-cols-1 md:grid-cols-12 gap-4 items-start">
              {/* Overview Prose */}
              <div className="md:col-span-7 lg:col-span-8 bg-white/90 p-4 rounded-xl border border-slate-300 shadow-sm leading-relaxed text-sm text-slate-800 space-y-2">
                <RichText text={overviewText} className="notes-prose" />
                <div className="text-xs font-mono text-slate-600 bg-slate-100 p-2 rounded border border-slate-200">
                  Source: {lecture.sourceMeta?.sourceFile || lecture.instructor || 'Imported analysis'} • Processed: {lecture.date}
                </div>
              </div>

              {/* Key Point Callout Box */}
              <div className="md:col-span-5 lg:col-span-4 notebook-callout-yellow p-4 space-y-2 relative">
                <div className="flex items-center justify-between text-amber-900">
                  <span className="font-handwriting font-bold text-sm flex items-center gap-1">
                    <Star className="w-4 h-4 text-amber-500 fill-amber-400" />
                    Key Point
                  </span>
                  <Lightbulb className="w-4 h-4 text-amber-600" />
                </div>
                <RichText text={simplifiedText} className="text-xs text-amber-950 font-medium leading-relaxed" />
              </div>
            </div>
          </div>}

          {/* 2. Structured Comparison Table */}
          {!hasAiGeneratedNotes && <div className="notes-section space-y-3">
            <div className="notes-section-heading flex items-center gap-2">
              <span className="w-2.5 h-2.5 rounded-full bg-indigo-600"></span>
              <h3 className="text-base sm:text-lg font-bold font-handwriting text-indigo-900 border-b border-indigo-200 inline-block">
                2. {targetLang === 'hi' ? 'अवधारणा तुलना और कोड तालिका' : targetLang === 'bn' ? 'কনসেপ্ট তুলনা ও কোড টেবিল' : targetLang === 'ar' ? 'جدول مقارنة المفاهيم' : 'Structured Concept Breakdown & Code Table'}
              </h3>
            </div>

            <div className="overflow-x-auto rounded-xl border-2 border-slate-700 shadow-md">
              <table className="notebook-table">
                <thead>
                  <tr>
                    <th className="w-1/4"># Concept Name</th>
                    <th className="w-1/2">Detailed Explanation ({langInfo.nativeName})</th>
                    <th className="w-1/4">Key Property</th>
                  </tr>
                </thead>
                <tbody>
                  {conceptsList.map((item, idx) => (
                    <tr key={idx} className={idx % 2 === 0 ? 'bg-white' : 'bg-slate-50/70'}>
                      <td className="font-bold text-indigo-900 font-handwriting">
                        {idx + 1}. {item.concept}
                      </td>
                      <td className="text-slate-800">
                        <RichText text={item.explanation} />
                      </td>
                      <td>
                        <span className="inline-block px-2 py-0.5 text-xs font-mono font-semibold bg-indigo-100 text-indigo-800 rounded border border-indigo-200">
                          {item.explanation.split(/[.;:]/)[0].trim().slice(0, 48) || 'Concept detail'}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>}

          {lecture.chapters && lecture.chapters.length > 0 && (
            <div className="notes-section space-y-3">
              <ChapterFlowchart chapters={lecture.chapters} />
            </div>
          )}

          {pages.length > 0 && (
            <div className="notes-section space-y-3">
              <div className="notes-section-heading flex items-center gap-2">
                <span className="w-2.5 h-2.5 rounded-full bg-cyan-600"></span>
                <h3 className="text-base sm:text-lg font-bold font-handwriting text-cyan-900 border-b border-cyan-200 inline-block">
                  Imported Section Notes
                </h3>
              </div>

              <div className="source-section-grid">
                {pages.map((page) => (
                  <article key={page.id} className="source-section-card">
                    <div className="source-section-card-heading">
                      <div>
                        <h4>{page.localized?.[targetLang]?.title || page.title}</h4>
                        <span>{page.timestamp}{page.endTimestamp && page.endTimestamp !== '—' ? `–${page.endTimestamp}` : ''} • Section {page.pageNumber}</span>
                      </div>
                      <span className="source-section-badge">{page.diagrams.length ? 'Visual' : 'Notes'}</span>
                    </div>
                    {(page.localized?.[targetLang]?.extractedText || page.extractedText) && (
                      <RichText text={page.localized?.[targetLang]?.extractedText || page.extractedText} />
                    )}
                    {(page.localized?.[targetLang]?.handwrittenNotes || page.handwrittenNotes).length > 0 && (
                      <ul>
                        {(page.localized?.[targetLang]?.handwrittenNotes || page.handwrittenNotes).slice(0, 5).map((note, index) => (
                          <li key={`${page.id}-note-${index}`}><RichText text={note} as="span" /></li>
                        ))}
                      </ul>
                    )}
                    {page.spokenHighlights && page.spokenHighlights.length > 0 && (
                      <div className="source-section-spoken">
                        <span>Spoken highlights</span>
                        {page.spokenHighlights.slice(0, 4).map((highlight, index) => (
                          <p key={`${page.id}-spoken-${index}`}>
                            <strong>{highlight.timestamp}{highlight.endTimestamp && highlight.endTimestamp !== '—' ? `–${highlight.endTimestamp}` : ''}</strong>
                            <RichText text={highlight.text} as="span" />
                          </p>
                        ))}
                      </div>
                    )}
                  </article>
                ))}
              </div>
            </div>
          )}

          {lecture.transcript.length > 0 && (
            <div className="notes-section notes-transcript-section space-y-3">
              <div className="notes-section-heading flex items-center gap-2">
                <span className="w-2.5 h-2.5 rounded-full bg-blue-600"></span>
                <h3 className="text-base sm:text-lg font-bold font-handwriting text-blue-900 border-b border-blue-200 inline-block">
                  {targetLang === 'hi' ? 'शिक्षक ऑडियो स्क्रिप्ट और ट्रांसक्रिप्ट' : targetLang === 'bn' ? 'শিক্ষকের অডিও স্ক্রিপ্ট ও ট্রান্সক্রিপ্ট' : targetLang === 'ar' ? 'نص المعلم الصوتي والتفريغ' : 'Teacher Audio Script & Transcript'}
                </h3>
              </div>

              <div className="notes-transcript-list">
                {lecture.transcript.map((segment) => (
                  <article key={segment.id} className="notes-transcript-card">
                    <div className="notes-transcript-meta">
                      <span className="notes-transcript-timestamp">
                        ◷ {segment.timestamp}{segment.endTimestamp && segment.endTimestamp !== '—' ? `–${segment.endTimestamp}` : ''}
                      </span>
                      <span className="notes-transcript-speaker">{segment.speaker}</span>
                    </div>

                    <RichText text={`"${segment.originalEnglishText}"`} className="notes-transcript-original" />

                    <div
                      dir={langInfo.dir}
                      className="notes-transcript-translation"
                      style={{ fontFamily: langInfo.fontFamily }}
                    >
                      <span>{langInfo.flag} {langInfo.nativeName}</span>
                      <RichText text={segment.translations[targetLang] || segment.originalEnglishText} />
                    </div>
                  </article>
                ))}
              </div>
            </div>
          )}

          {/* 3. Mathematical Formulas */}
          {activePage && activePage.formulas && activePage.formulas.length > 0 && (!hasAiGeneratedNotes || !aiHasFormula) && (
            <div className="notes-section space-y-3">
              <div className="notes-section-heading flex items-center gap-2">
                <span className="w-2.5 h-2.5 rounded-full bg-purple-600"></span>
                <h3 className="text-base sm:text-lg font-bold font-handwriting text-purple-900 border-b border-purple-200 inline-block">
                  3. {targetLang === 'hi' ? 'संरक्षित गणितीय सूत्र' : targetLang === 'bn' ? 'সংরক্ষিত গাণিতিক সূত্র' : targetLang === 'ar' ? 'الصيغ الرياضية المحفوظة' : 'Preserved Formulas & Mathematical Proofs'}
                </h3>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {activePage.formulas.map((form) => {
                  const desc = form.description[targetLang] || form.description.en;
                  const breakdown = form.variableBreakdown[targetLang] || form.variableBreakdown.en;

                  return (
                    <div key={form.id} className="notebook-callout-blue p-4 space-y-3">
                      <div className="flex items-center justify-between text-blue-900 border-b border-blue-200 pb-1.5">
                        <span className="font-handwriting font-bold text-sm flex items-center gap-1.5">
                          <Code2 className="w-4 h-4 text-blue-600" />
                          Formula Definition
                        </span>
                        <span className="text-[10px] font-mono font-bold bg-blue-200 text-blue-900 px-2 py-0.5 rounded">
                          LaTeX Preserved
                        </span>
                      </div>

                      {/* KaTeX Math Box */}
                      <div className="bg-white p-3 rounded-lg border border-blue-300 shadow-inner flex items-center justify-center">
                        <div id={`katex-${form.id}`} className="text-base font-serif font-bold text-slate-900" />
                      </div>

                      <RichText text={desc} className="text-xs text-blue-950 font-medium leading-relaxed" />

                      {breakdown && Object.keys(breakdown).length > 0 && (
                        <div className="bg-blue-100/60 p-2.5 rounded-lg text-xs space-y-1 font-mono text-slate-800">
                          <span className="font-bold text-blue-900 text-[10px] uppercase tracking-wider block font-sans">
                            Variable Breakdown:
                          </span>
                          {Object.entries(breakdown).map(([vKey, vVal]) => (
                            <div key={vKey} className="flex justify-between text-[11px]">
                              <span className="font-bold text-blue-700">{vKey}</span>
                              <span>{vVal}</span>
                            </div>
                          ))}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            </div>
          )}

          {/* 4. Visual Diagram */}
          {activePage.diagrams && activePage.diagrams.length > 0 && (
            <div className="notes-section space-y-3">
              <div className="notes-section-heading flex items-center gap-2">
                <span className="w-2.5 h-2.5 rounded-full bg-emerald-600"></span>
                <h3 className="text-base sm:text-lg font-bold font-handwriting text-emerald-900 border-b border-emerald-200 inline-block">
                  4. Visual Diagram & Chart Illustration
                </h3>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-4 items-center">
                <div className="bg-white p-3 rounded-xl border-2 border-slate-300 shadow-sm flex flex-col items-center justify-center">
                  <span className="text-xs font-handwriting font-bold text-slate-600 mb-2">
                    [Clean Visual Representation]
                  </span>
                  <div
                    className="notes-diagram-preview"
                    dangerouslySetInnerHTML={{ __html: activePage.diagrams[0].cleanDiagramSvg }}
                  />
                </div>

                <div className="notebook-callout-green p-4 space-y-2">
                  <h4 className="text-xs font-bold font-handwriting text-emerald-900 flex items-center gap-1">
                    <CheckCircle2 className="w-4 h-4 text-emerald-600" />
                    Diagram Key Takeaways ({langInfo.nativeName})
                  </h4>
                  <RichText
                    text={activePage.diagrams[0].explanations[targetLang] || activePage.diagrams[0].explanations.en}
                    className="text-xs text-emerald-950 leading-relaxed font-medium"
                  />
                  <ul className="space-y-1 text-xs text-emerald-900 font-medium">
                    {(activePage.diagrams[0].keyTakeaways[targetLang] || activePage.diagrams[0].keyTakeaways.en).map((t, i) => (
                      <li key={i} className="flex items-center gap-1.5">
                        <span className="text-emerald-600 font-bold">✓</span>
                        <RichText text={t} as="span" />
                      </li>
                    ))}
                  </ul>
                </div>
              </div>
            </div>
          )}

          {/* 5. Technical Glossary Grid */}
          {!hasAiGeneratedNotes && <div className="notes-section space-y-3">
            <div className="notes-section-heading flex items-center gap-2">
              <span className="w-2.5 h-2.5 rounded-full bg-amber-600"></span>
              <h3 className="text-base sm:text-lg font-bold font-handwriting text-amber-900 border-b border-amber-200 inline-block">
                5. Technical Terms Glossary
              </h3>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
              {techTermsList.map((termItem, idx) => (
                <div key={idx} className="bg-amber-50/70 p-3 rounded-xl border border-amber-300 space-y-1 shadow-sm">
                  <span className="text-xs font-bold font-handwriting text-amber-950 block border-b border-amber-200 pb-1">
                    📌 {termItem.term}
                  </span>
                  <RichText text={termItem.definition} className="text-[11px] text-slate-700 leading-relaxed" />
                </div>
              ))}
            </div>
          </div>}

          {/* Notebook Summary Callout & Footer Banner */}
          {!hasAiGeneratedNotes && <div className="border-2 border-slate-800 rounded-xl p-4 bg-slate-50/90 space-y-2 shadow-md">
            <div className="flex items-center justify-between border-b border-slate-300 pb-2">
              <span className="font-handwriting font-bold text-sm text-slate-900 flex items-center gap-1.5">
                <BookOpen className="w-4 h-4 text-indigo-600" />
                Notebook Summary & Takeaway
              </span>
              <Smile className="w-5 h-5 text-amber-500" />
            </div>
            <RichText text={simplifiedText} className="notes-prose text-xs font-medium text-slate-800 leading-relaxed" />
            <div className="pt-2 text-center text-xs font-bold font-handwriting text-slate-900 border-t border-slate-300 tracking-wider">
              ★ Build Smart. Organize Better. Code & Learn with AI! ★
            </div>
          </div>}

        </div>
      </div>
    </div>
  );
};
