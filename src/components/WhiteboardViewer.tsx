import React, { useState } from 'react';
import type { WhiteboardPage, TranscriptSegment, TargetLanguage } from '../types';
import { getLanguageInfo } from '../types';
import { Monitor, Mic, Clock, FileText, ChevronLeft, ChevronRight, Volume2, Upload, Sparkles } from 'lucide-react';
import { RichText } from './RichText';

interface WhiteboardViewerProps {
  pages: WhiteboardPage[];
  transcript: TranscriptSegment[];
  activePageId: string;
  onSelectPage: (pageId: string) => void;
  targetLang: TargetLanguage;
  onOpenUploadModal: () => void;
  aiGenerated?: boolean;
}

export const WhiteboardViewer: React.FC<WhiteboardViewerProps> = ({
  pages,
  transcript,
  activePageId,
  onSelectPage,
  targetLang,
  onOpenUploadModal,
  aiGenerated = false
}) => {
  const [showTranscript, setShowTranscript] = useState(true);

  const activePageIndex = pages.findIndex((p) => p.id === activePageId);
  const currentPage = pages[activePageIndex >= 0 ? activePageIndex : 0];

  const filteredTranscripts = transcript.filter(
    (t) => t.associatedPageId === currentPage.id
  );

  const langInfo = getLanguageInfo(targetLang);
  const currentPageContent = currentPage?.localized?.[targetLang] || {};
  // AI mode must never silently fall back to OCR. If Gemini did not return
  // analysis for this page, show the explicit empty state below instead.
  const hasAiSlideAnalysis = aiGenerated;
  const highlightNotes = aiGenerated
    ? currentPageContent.handwrittenNotes || []
    : currentPage?.handwrittenNotes || [];

  const renderBoardContent = () => {
    if (!currentPage || !currentPage.boardImageSvg) return null;
    const content = currentPage.boardImageSvg.trim();

    if (content.startsWith('<svg')) {
      return (
        <div
          className="w-full h-full flex items-center justify-center max-h-[400px]"
          dangerouslySetInnerHTML={{ __html: content }}
        />
      );
    } else {
      return (
        <img
          src={content}
          alt={`Smartboard Page ${currentPage.pageNumber}`}
          className="max-h-[380px] w-auto max-w-full object-contain rounded-lg shadow-sm"
        />
      );
    }
  };

  return (
    <div className="card-whiteboard-container space-y-5">
      
      {/* Header Bar */}
      <div className="whiteboard-header-bar border-b border-slate-200 pb-3.5">
        <div className="flex items-center gap-2.5">
          <div className="w-9 h-9 rounded-xl bg-blue-50 text-blue-600 border border-blue-200 flex items-center justify-center font-bold">
            <Monitor className="w-5 h-5" />
          </div>
          <div>
            <h2 className="text-sm font-bold text-slate-900 flex items-center gap-2">
              <span>Smartboard Slide {currentPage.pageNumber} of {pages.length}</span>
              <span className="pill-timestamp">
                ⏱ {currentPage.timestamp}{currentPage.endTimestamp && currentPage.endTimestamp !== '—' ? `–${currentPage.endTimestamp}` : ''}
              </span>
            </h2>
            <p className="text-xs text-slate-500 font-medium">{currentPageContent.title || currentPage.title}</p>
          </div>
        </div>

        {/* Slide Selector Controls */}
        <div className="smartboard-controls flex items-center gap-2">
          <button
            type="button"
            disabled={activePageIndex <= 0}
            onClick={() => onSelectPage(pages[activePageIndex - 1].id)}
            className="p-1.5 rounded-lg bg-slate-100 hover:bg-slate-200 text-slate-700 border border-slate-200 disabled:opacity-30 disabled:cursor-not-allowed transition-all"
            title="Previous Slide"
          >
            <ChevronLeft className="w-4 h-4" />
          </button>

          <div className="slide-selector-track" aria-label="Choose a smartboard slide">
            <div className="slide-selector-list">
              {pages.map((p, idx) => (
                <button
                  key={p.id}
                  type="button"
                  onClick={() => onSelectPage(p.id)}
                  className={`px-3 py-1 rounded-lg text-xs font-bold font-mono transition-all ${
                    p.id === currentPage.id
                      ? 'bg-blue-600 text-white font-extrabold shadow-sm'
                      : 'bg-slate-100 text-slate-600 hover:bg-slate-200 border border-slate-200'
                  }`}
                >
                  Slide {idx + 1}
                </button>
              ))}
            </div>
          </div>

          <button
            type="button"
            disabled={activePageIndex >= pages.length - 1}
            onClick={() => onSelectPage(pages[activePageIndex + 1].id)}
            className="p-1.5 rounded-lg bg-slate-100 hover:bg-slate-200 text-slate-700 border border-slate-200 disabled:opacity-30 disabled:cursor-not-allowed transition-all"
            title="Next Slide"
          >
            <ChevronRight className="w-4 h-4" />
          </button>

          <button
            type="button"
            onClick={onOpenUploadModal}
            className="btn-add-page"
          >
            <Upload className="w-3.5 h-3.5" />
            <span>Upload Slide</span>
          </button>
        </div>
      </div>

      {/* Main Grid: Smartboard View + Transcript */}
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
        
        {/* Left 7 Cols: Smartboard Canvas View */}
        <div className="lg:col-span-7 space-y-3">
          <div className="smartboard-screen-frame smartboard-preview-frame flex flex-col items-center justify-center">
            {renderBoardContent()}
            
            <div className="absolute top-3 left-3 bg-slate-900/90 backdrop-blur-md px-3 py-1 rounded-lg border border-blue-400/40 flex items-center gap-1.5 text-[11px] font-semibold text-blue-300 shadow-md">
              <Sparkles className="w-3.5 h-3.5 text-blue-400" />
              <span>Smartboard Active</span>
            </div>
          </div>

          {/* AI-written slide explanation and takeaways */}
          <div className="card-highlights space-y-2">
            <h4 className="text-xs font-bold uppercase tracking-wider text-amber-900 flex items-center gap-1.5">
              {hasAiSlideAnalysis ? <Sparkles className="w-4 h-4 text-amber-600" /> : <FileText className="w-4 h-4 text-amber-600" />}
              {hasAiSlideAnalysis ? 'AI Slide Analysis & Highlights' : 'Whiteboard Text & Highlight Snippets'}
            </h4>
            {hasAiSlideAnalysis && currentPageContent.extractedText && (
              <RichText text={currentPageContent.extractedText} className="slide-ai-description" />
            )}
            {highlightNotes.length > 0 ? (
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                {highlightNotes.map((note, idx) => (
                  <div key={idx} className="highlight-snippet-pill">
                    <span className="text-amber-600 font-bold">•</span>
                    <span>{note}</span>
                  </div>
                ))}
              </div>
            ) : (
              <p className="slide-ai-empty">
                Gemini did not return takeaways for this slide. Re-run note generation to analyze it.
              </p>
            )}
          </div>
        </div>

        {/* Right 5 Cols: Audio Speech Transcript */}
        <div className="lg:col-span-5 space-y-3">
          <div className="transcript-header-bar">
            <div className="flex items-center gap-2">
              <div className="w-6 h-6 rounded-lg bg-blue-100 text-blue-700 flex items-center justify-center font-bold">
                <Mic className="w-3.5 h-3.5" />
              </div>
              <h3 className="text-xs font-bold text-slate-800">
                Synced Teacher Audio Transcript
              </h3>
            </div>
            <button
              type="button"
              onClick={() => setShowTranscript(!showTranscript)}
              className="btn-transcript-toggle"
            >
              {showTranscript ? 'Hide' : 'Show'}
            </button>
          </div>

          {showTranscript && (
            <div className="space-y-3 max-h-[380px] overflow-y-auto pr-1">
              {filteredTranscripts.length === 0 ? (
                <div className="p-6 text-center text-xs text-slate-500 bg-slate-50 rounded-xl border border-slate-200">
                  No transcript audio segment tied to this page.
                </div>
              ) : (
                filteredTranscripts.map((t) => (
                  <div key={t.id} className="transcript-bubble-card space-y-2">
                    <div className="flex items-center justify-between text-xs">
                      <span className="pill-timestamp flex items-center gap-1">
                        <Clock className="w-3 h-3" />
                        {t.timestamp}{t.endTimestamp && t.endTimestamp !== '—' ? `–${t.endTimestamp}` : ''} • {t.speaker}
                      </span>
                      <span className="text-[10px] font-bold bg-blue-100 text-blue-800 border border-blue-200 px-2 py-0.5 rounded-full flex items-center gap-1">
                        <Volume2 className="w-3 h-3 text-blue-600" />
                        {langInfo.flag} {langInfo.name}
                      </span>
                    </div>

                    <p className="quote-original-english">
                      "{t.originalEnglishText}"
                    </p>

                    <div
                      dir={langInfo.dir}
                      className="translation-target-box"
                      style={{ fontFamily: langInfo.fontFamily }}
                    >
                      {t.translations[targetLang] || t.originalEnglishText}
                    </div>
                  </div>
                ))
              )}
            </div>
          )}
        </div>

      </div>

    </div>
  );
};
