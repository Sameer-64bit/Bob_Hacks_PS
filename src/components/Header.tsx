import React, { useState } from 'react';
import type { TargetLanguage, Lecture } from '../types';
import { createCustomLanguage, getLanguageInfo, SUPPORTED_LANGUAGES } from '../types';
import {
  Download,
  Languages,
  BookOpen,
  Plus,
  GraduationCap,
  ChevronDown,
  FileText,
  Presentation,
  Sparkles,
  PenLine
} from 'lucide-react';

interface HeaderProps {
  currentLang: TargetLanguage;
  onLanguageChange: (lang: TargetLanguage) => void;
  lectures: Lecture[];
  activeLecture: Lecture;
  onSelectLecture: (lecture: Lecture) => void;
  onExportPDF: () => void;
  onDownloadTeacherBoards: () => void;
  onDownloadTeacherDrawing: () => void;
  onDownloadAiVectorBoard: () => void;
  hasAiVectorBoard: boolean;
  onOpenNewModal: () => void;
  translationLoading?: boolean;
  translationError?: string;
}

export const Header: React.FC<HeaderProps> = ({
  currentLang,
  onLanguageChange,
  lectures,
  activeLecture,
  onSelectLecture,
  onExportPDF,
  onDownloadTeacherBoards,
  onDownloadTeacherDrawing,
  onDownloadAiVectorBoard,
  hasAiVectorBoard,
  onOpenNewModal,
  translationLoading = false,
  translationError = ''
}) => {
  const [isDownloadMenuOpen, setIsDownloadMenuOpen] = useState(false);
  const [customLanguageInput, setCustomLanguageInput] = useState('');

  const closeDownloadMenu = () => setIsDownloadMenuOpen(false);
  const currentLangInfo = getLanguageInfo(currentLang);
  const compactTranslationError = translationError
    ? translationError.split(/\r?\n/)[0].slice(0, 120)
    : '';
  const languageOptions = [
    ...Object.values(SUPPORTED_LANGUAGES),
    ...(currentLangInfo.code.startsWith('custom:') ? [currentLangInfo] : [])
  ];

  const handleCustomLanguageSubmit = (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const customLanguage = createCustomLanguage(customLanguageInput);
    if (!customLanguage) return;
    onLanguageChange(customLanguage.code);
    setCustomLanguageInput('');
  };

  return (
    <header className="app-header bg-white border-b border-slate-200 px-4 lg:px-8 py-3 sticky top-0 z-40 shadow-sm">
      <div className="app-header-inner max-w-7xl mx-auto flex flex-col md:flex-row items-center justify-between gap-4">
        
        {/* Brand Logo */}
        <div className="app-brand flex items-center gap-3">
          <div className="w-10 h-10 brand-logo-icon shrink-0">
            <GraduationCap className="w-6 h-6 text-white" />
          </div>

          <div className="app-brand-copy">
            <div className="flex items-center gap-2">
              <h1 className="app-brand-title text-lg font-bold text-slate-900 tracking-tight">SmartClass AI</h1>
              <span className="app-brand-badge text-[10px] uppercase font-bold bg-blue-50 text-blue-700 px-2 py-0.5 border border-blue-200 rounded-md">
                Multilingual Classroom Assistant
              </span>
            </div>
            <p className="text-xs text-slate-500 font-medium">
              Transforming Board Sketches, Graphs & Spoken Lectures into Clean Notes
            </p>
          </div>
        </div>

        {/* Center: Lecture Selector Pill */}
        <div className="lecture-picker flex items-center gap-2 bg-slate-50 p-1.5 rounded-xl border border-slate-200 shadow-inner">
          <div className="flex items-center gap-1.5 px-2 text-blue-600">
            <BookOpen className="w-4 h-4" />
            <span className="text-xs font-bold text-slate-500 hidden sm:inline">Lecture:</span>
          </div>

          <select
            value={activeLecture.id}
            onChange={(e) => {
              const selected = lectures.find((l) => l.id === e.target.value);
              if (selected) onSelectLecture(selected);
            }}
            className="custom-select-pill"
          >
            {lectures.map((l) => (
              <option key={l.id} value={l.id} className="bg-white text-slate-900">
                {l.subject}: {l.title}
              </option>
            ))}
          </select>

          <button
            type="button"
            onClick={onOpenNewModal}
            className="btn-add-page"
            title="Upload/Process New Board Page"
          >
            <Plus className="w-3.5 h-3.5" />
            <span className="hidden sm:inline">Add Page</span>
          </button>
        </div>

        {/* Right: Download Action */}
        <div className="header-actions flex items-center gap-3">
          {/* Download Menu */}
          <div className="download-menu">
            <button
              type="button"
              onClick={() => setIsDownloadMenuOpen((open) => !open)}
              className="btn-export-pdf download-menu-trigger"
              aria-haspopup="menu"
              aria-expanded={isDownloadMenuOpen}
            >
              <Download className="w-4 h-4" />
              <span>Download</span>
              <ChevronDown className={`w-3.5 h-3.5 transition-transform ${isDownloadMenuOpen ? 'download-menu-chevron-open' : ''}`} />
            </button>

            {isDownloadMenuOpen && (
              <div className="download-menu-panel" role="menu">
                <div className="download-menu-heading">Choose what to download</div>

                <button
                  type="button"
                  role="menuitem"
                  onClick={() => {
                    closeDownloadMenu();
                    onExportPDF();
                  }}
                  className="download-menu-item"
                >
                  <FileText className="download-menu-icon text-rose-600" />
                  <span>
                    <strong>Handwritten notes</strong>
                    <small>Printable PDF</small>
                  </span>
                  <span className="download-menu-format">PDF</span>
                </button>

                <button
                  type="button"
                  role="menuitem"
                  onClick={() => {
                    closeDownloadMenu();
                    onDownloadTeacherBoards();
                  }}
                  className="download-menu-item"
                >
                  <Presentation className="download-menu-icon text-blue-600" />
                  <span>
                    <strong>Teacher board slides</strong>
                    <small>All slides from this lecture</small>
                  </span>
                  <span className="download-menu-format">PDF</span>
                </button>

                <button
                  type="button"
                  role="menuitem"
                  disabled={!hasAiVectorBoard}
                  onClick={() => {
                    closeDownloadMenu();
                    onDownloadTeacherDrawing();
                  }}
                  className="download-menu-item"
                >
                  <PenLine className="download-menu-icon text-amber-600" />
                  <span>
                    <strong>Teacher board drawing</strong>
                    <small>Original rough diagram</small>
                  </span>
                  <span className="download-menu-format">SVG</span>
                </button>

                <button
                  type="button"
                  role="menuitem"
                  disabled={!hasAiVectorBoard}
                  onClick={() => {
                    closeDownloadMenu();
                    onDownloadAiVectorBoard();
                  }}
                  className="download-menu-item"
                >
                  <Sparkles className="download-menu-icon text-emerald-600" />
                  <span>
                    <strong>AI vector board</strong>
                    <small>Clean active diagram</small>
                  </span>
                  <span className="download-menu-format">SVG</span>
                </button>
              </div>
            )}
          </div>

        </div>

      </div>

      {/* Dedicated multilingual control: always visible and independent from
          the lecture picker and download actions. */}
      <div className="language-bar max-w-7xl mx-auto" aria-label="Multilingual content selector">
        <div className="language-bar-label">
          <Languages className="w-4 h-4 text-blue-600" />
          <span>Translate content to</span>
          <span className="language-bar-hint">Notes, transcript, diagrams & tutor</span>
        </div>

        <div className="language-bar-options">
          <div className="lang-pill-container" role="group" aria-label="Choose content language">
            {languageOptions.map((info) => {
            const langCode = info.code;
            const isActive = currentLang === langCode;
            return (
              <button
                key={langCode}
                type="button"
                onClick={() => onLanguageChange(langCode)}
                className={`lang-pill-btn ${isActive ? 'lang-pill-btn-active' : ''}`}
                aria-pressed={isActive}
                aria-label={`Use ${info.name}`}
              >
                <span>{info.flag}</span>
                <span>{info.nativeName}</span>
              </button>
            );
            })}
          </div>

          <form className="custom-language-form" onSubmit={handleCustomLanguageSubmit}>
            <input
              value={customLanguageInput}
              onChange={(event) => setCustomLanguageInput(event.target.value)}
              className="custom-language-input"
              aria-label="Translate to another language"
              placeholder="Any language…"
            />
            <button
              type="submit"
              className="custom-language-button"
              disabled={!customLanguageInput.trim() || translationLoading}
            >
              Translate
            </button>
          </form>
        </div>

        <div className="language-bar-current">
          <span>Active:</span>
          <strong>{currentLangInfo.nativeName}</strong>
          {translationLoading && <span className="language-translation-status">Translating…</span>}
          {!translationLoading && translationError && (
            <span className="language-translation-error" title={translationError}>
              {compactTranslationError}
            </span>
          )}
        </div>
      </div>
    </header>
  );
};
