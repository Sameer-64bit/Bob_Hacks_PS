import { useEffect, useRef, useState } from 'react';
import type { Lecture, TargetLanguage, WhiteboardPage } from './types';
import { getLanguageInfo } from './types';
import { SAMPLE_LECTURES } from './data/sampleLectures';
import { Header } from './components/Header';
import { WhiteboardViewer } from './components/WhiteboardViewer';
import { DiagramComparison } from './components/DiagramComparison';
import { MultilingualNotesView } from './components/MultilingualNotesView';
import { LectureQABot } from './components/LectureQABot';
import { NewLectureModal } from './components/NewLectureModal';
import { exportLectureNotesToPDF, exportTeacherBoardSlidesToPDF } from './services/pdfExport';
import { translateLectureWithAI } from './services/notesPipeline';
import { createSafeDownloadName, downloadSvgFile } from './services/fileDownloads';
import { Monitor, Network, FileSpreadsheet, MessageSquare, Layers, Calculator, Split } from 'lucide-react';

export type WorkspaceTab = 'notes' | 'board' | 'diagrams' | 'tutor';

export function App() {
  const [lectures, setLectures] = useState<Lecture[]>(SAMPLE_LECTURES);
  const [activeLectureId, setActiveLectureId] = useState<string>(SAMPLE_LECTURES[0].id);
  const [targetLang, setTargetLang] = useState<TargetLanguage>('en');
  const [activePageId, setActivePageId] = useState<string>(SAMPLE_LECTURES[0].pages[0].id);
  const [activeTab, setActiveTab] = useState<WorkspaceTab>('notes');
  const [splitViewMode, setSplitViewMode] = useState<boolean>(false);
  const [isModalOpen, setIsModalOpen] = useState<boolean>(false);
  const [uploadMode, setUploadMode] = useState<'lecture' | 'pdf'>('lecture');
  const [translationLoading, setTranslationLoading] = useState(false);
  const [translationError, setTranslationError] = useState('');
  const translationRequestId = useRef(0);

  const activeLecture = lectures.find((l: Lecture) => l.id === activeLectureId) || lectures[0];
  const activePage = activeLecture.pages.find((p: WhiteboardPage) => p.id === activePageId) || activeLecture.pages[0];
  const hasActiveDiagram = Boolean(activePage?.diagrams?.length);

  useEffect(() => {
    if (activeTab === 'diagrams' && !hasActiveDiagram) {
      setActiveTab('notes');
    }
  }, [activeTab, hasActiveDiagram]);

  const isSourceLanguage = (language: TargetLanguage): boolean => {
    const sourceLanguage = activeLecture.sourceMeta?.language?.trim().toLowerCase();
    const selectedLanguage = getLanguageInfo(language);
    const selectedCode = language.trim().toLowerCase();
    const selectedName = selectedLanguage.name.trim().toLowerCase();

    // English is the app's preserved source-language fallback when the source
    // metadata is missing, which prevents an unnecessary Gemini round-trip
    // when the user returns from a translated view to English.
    if (selectedCode === 'en' && (!sourceLanguage || sourceLanguage === 'en' || sourceLanguage === 'english')) {
      return true;
    }

    return Boolean(sourceLanguage && (sourceLanguage === selectedCode || sourceLanguage === selectedName));
  };

  const handleLanguageChange = async (language: TargetLanguage) => {
    const previousLanguage = targetLang;
    setTranslationError('');
    setTargetLang(language);

    if (language === previousLanguage) return;

    const requestId = ++translationRequestId.current;
    if (isSourceLanguage(language)) {
      setTranslationLoading(false);
      return;
    }

    if (activeLecture.generation?.generatedLanguages.includes(language)) {
      setTranslationLoading(false);
      return;
    }

    setTranslationLoading(true);
    try {
      const translatedLecture = await translateLectureWithAI(activeLecture, language);
      if (requestId !== translationRequestId.current) return;

      setLectures((currentLectures) => currentLectures.map((lecture) => (
        lecture.id === translatedLecture.id ? translatedLecture : lecture
      )));
    } catch (error) {
      if (requestId !== translationRequestId.current) return;
      setTargetLang(previousLanguage);
      const errorText = error instanceof Error ? error.message : 'Unable to translate this lecture.';
      setTranslationError(/quota|rate limit|429|billing/i.test(errorText)
        ? 'Gemini translation quota is temporarily exhausted. Wait and retry, or enable Gemini billing/use another API key.'
        : errorText);
    } finally {
      if (requestId === translationRequestId.current) setTranslationLoading(false);
    }
  };

  const handleSelectLecture = (lec: Lecture) => {
    setActiveLectureId(lec.id);
    if (lec.pages.length > 0) {
      setActivePageId(lec.pages[0].id);
    }
  };

  const handleAddPage = (newPage: WhiteboardPage) => {
    const updated = lectures.map((l: Lecture) => {
      if (l.id === activeLecture.id) {
        return {
          ...l,
          pages: [...l.pages, newPage]
        };
      }
      return l;
    });
    setLectures(updated);
    setActivePageId(newPage.id);
  };

  const handleImportLecture = (lecture: Lecture) => {
    setLectures((currentLectures) => [...currentLectures, lecture]);
    setActiveLectureId(lecture.id);
    setActivePageId(lecture.pages[0]?.id || '');
    setActiveTab('notes');
    setSplitViewMode(false);
  };

  const handleExportPDF = async () => {
    if (activeTab !== 'notes' && !splitViewMode) {
      setActiveTab('notes');
      await new Promise((resolve) => setTimeout(resolve, 300));
    }
    await exportLectureNotesToPDF(activeLecture, targetLang, 'printable-notes-container');
  };

  const getActiveSlideDownloadPrefix = () =>
    `${createSafeDownloadName(activeLecture.subject)}_${createSafeDownloadName(activeLecture.title)}_Slide_${activePage.pageNumber}`;

  const handleDownloadTeacherBoards = async () => {
    await exportTeacherBoardSlidesToPDF(activeLecture);
  };

  const handleDownloadTeacherDrawing = () => {
    const teacherDrawing = activePage.diagrams[0]?.roughSketchSvg;
    if (!teacherDrawing) return;

    downloadSvgFile(
      teacherDrawing,
      `${getActiveSlideDownloadPrefix()}_Teacher_Drawing.svg`
    );
  };

  const handleDownloadAiVectorBoard = () => {
    const aiVectorBoard = activePage.diagrams[0]?.cleanDiagramSvg;
    if (!aiVectorBoard) return;

    downloadSvgFile(
      aiVectorBoard,
      `${getActiveSlideDownloadPrefix()}_AI_Vector_Board.svg`
    );
  };

  const openLectureUpload = () => {
    setUploadMode('lecture');
    setIsModalOpen(true);
  };

  const openPdfSlideUpload = () => {
    setUploadMode('pdf');
    setIsModalOpen(true);
  };

  const currentLangInfo = getLanguageInfo(targetLang);

  return (
    <div className="app-shell min-h-screen bg-[#f8fafc] text-slate-900 flex flex-col font-sans selection:bg-blue-600 selection:text-white">
      
      {/* Light Theme Header */}
      <Header
        currentLang={targetLang}
        onLanguageChange={handleLanguageChange}
        lectures={lectures}
        activeLecture={activeLecture}
        onSelectLecture={handleSelectLecture}
        onExportPDF={handleExportPDF}
        onDownloadTeacherBoards={handleDownloadTeacherBoards}
        onDownloadTeacherDrawing={handleDownloadTeacherDrawing}
        onDownloadAiVectorBoard={handleDownloadAiVectorBoard}
        hasAiVectorBoard={activePage.diagrams.length > 0}
        onOpenNewModal={openLectureUpload}
        translationLoading={translationLoading}
        translationError={translationError}
      />

      {/* Main Light Workspace Container */}
      <main className="app-main flex-1 max-w-7xl w-full mx-auto px-4 lg:px-8 py-6 space-y-6">
        
        {/* Workspace Navigation Bar */}
        <div className="workspace-nav flex flex-col lg:flex-row items-stretch lg:items-center justify-between gap-4 bg-white border border-slate-200 p-2.5 rounded-2xl shadow-sm">
          
          {/* Workspace Tabs Bar */}
          <div className="workspace-tabs-bar flex-1 overflow-x-auto">
            <button
              type="button"
              onClick={() => setActiveTab('notes')}
              className={`tab-btn ${activeTab === 'notes' ? 'tab-btn-active' : ''}`}
            >
              <FileSpreadsheet className="w-4 h-4" />
              <span>📖 Handwritten Digital Notes</span>
            </button>

            <button
              type="button"
              onClick={() => setActiveTab('board')}
              className={`tab-btn ${activeTab === 'board' ? 'tab-btn-active' : ''}`}
            >
              <Monitor className="w-4 h-4" />
              <span>Smartboard & Speech Sync</span>
            </button>

            <button
              type="button"
              disabled={!hasActiveDiagram}
              onClick={() => {
                if (hasActiveDiagram) setActiveTab('diagrams');
              }}
              title={hasActiveDiagram ? 'Open diagram and graph cleaner' : 'This slide has no graphs or diagrams'}
              aria-label={hasActiveDiagram ? 'Diagram & Graph Cleaner' : 'Diagram & Graph Cleaner unavailable for this slide'}
              className={`tab-btn ${activeTab === 'diagrams' && hasActiveDiagram ? 'tab-btn-active' : ''}`}
            >
              <Network className="w-4 h-4" />
              <span>Diagram & Graph Cleaner</span>
              <span className={`text-[10px] px-1.5 py-0.2 font-mono font-bold rounded ${activeTab === 'diagrams' ? 'bg-white/20 text-white' : 'bg-slate-100 text-slate-700'}`}>
                {activePage.diagrams.length}
              </span>
            </button>

            <button
              type="button"
              onClick={() => setActiveTab('tutor')}
              className={`tab-btn ${activeTab === 'tutor' ? 'tab-btn-active' : ''}`}
            >
              <MessageSquare className="w-4 h-4" />
              <span>AI Classroom Tutor</span>
            </button>
          </div>

          {/* Quick Metrics & Split View Toggle */}
          <div className="flex items-center justify-between lg:justify-end gap-3 text-xs text-slate-600 font-medium px-2 shrink-0">
            <div className="flex items-center gap-2">
              <span className="metric-badge-pill">
                <Layers className="w-3.5 h-3.5 text-blue-600" />
                <strong className="text-slate-900">{activeLecture.pages.length}</strong> Slides
              </span>
              <span className="metric-badge-pill">
                <Calculator className="w-3.5 h-3.5 text-purple-600" />
                <strong className="text-slate-900">{activePage.formulas.length}</strong> Formulas
              </span>
              <span className="metric-badge-pill">
                <span>{currentLangInfo.flag}</span>
                <strong className="text-slate-900">{currentLangInfo.nativeName}</strong>
              </span>
            </div>

            {/* Split View Toggle Button */}
            <button
              type="button"
              onClick={() => setSplitViewMode(!splitViewMode)}
              className={`btn-split-view ${splitViewMode ? 'btn-split-view-active' : ''}`}
            >
              <Split className="w-3.5 h-3.5" />
              <span>{splitViewMode ? 'Single View' : 'Split View'}</span>
            </button>
          </div>

        </div>

        {/* Tab Workspace View Display */}
        {!splitViewMode ? (
          /* Single Focused Tab View */
          <div>
            {activeTab === 'notes' && (
              <MultilingualNotesView
                lecture={activeLecture}
                targetLang={targetLang}
                activePageId={activePageId}
              />
            )}

            {activeTab === 'board' && (
              <WhiteboardViewer
                pages={activeLecture.pages}
                transcript={activeLecture.transcript}
                activePageId={activePageId}
                onSelectPage={setActivePageId}
                targetLang={targetLang}
                onOpenUploadModal={openPdfSlideUpload}
                aiGenerated={activeLecture.generation?.aiGenerated}
              />
            )}

            {activeTab === 'diagrams' && (
              <DiagramComparison
                diagrams={activePage.diagrams}
                targetLang={targetLang}
              />
            )}

            {activeTab === 'tutor' && (
              <div className="max-w-3xl mx-auto">
                <LectureQABot
                  lecture={activeLecture}
                  targetLang={targetLang}
                />
              </div>
            )}
          </div>
        ) : (
          /* Split Dual View */
          <div className="grid grid-cols-1 lg:grid-cols-12 gap-6 items-start">
            <div className="lg:col-span-7 space-y-6">
              <MultilingualNotesView
                lecture={activeLecture}
                targetLang={targetLang}
                activePageId={activePageId}
              />
            </div>
            <div className="lg:col-span-5 space-y-6">
              <WhiteboardViewer
                pages={activeLecture.pages}
                transcript={activeLecture.transcript}
                activePageId={activePageId}
                onSelectPage={setActivePageId}
                targetLang={targetLang}
                onOpenUploadModal={openPdfSlideUpload}
                aiGenerated={activeLecture.generation?.aiGenerated}
              />
              <LectureQABot
                lecture={activeLecture}
                targetLang={targetLang}
              />
            </div>
          </div>
        )}

        {/* Hidden Printable Container if on other tabs */}
        {activeTab !== 'notes' && !splitViewMode && (
          <div className="fixed top-[-9999px] left-[-9999px] opacity-0 pointer-events-none">
            <MultilingualNotesView
              lecture={activeLecture}
              targetLang={targetLang}
              activePageId={activePageId}
            />
          </div>
        )}

      </main>

      {/* Light Theme Footer */}
      <footer className="mt-12 bg-white border-t border-slate-200 py-6 px-4 text-center text-xs text-slate-500 space-y-1">
        <p className="font-semibold text-slate-700">
          SmartClass AI — Multilingual University Classroom Assistant
        </p>
        <p>Speech & Vision LLM Fusion • Formula Preservation • Multilingual Handbook Synthesis (EN, HI, BN, AR)</p>
      </footer>

      {/* Ingestion Upload Modal */}
      <NewLectureModal
        isOpen={isModalOpen}
        onClose={() => setIsModalOpen(false)}
        onAddPage={handleAddPage}
        onImportLecture={handleImportLecture}
        currentLang={targetLang}
        mode={uploadMode}
      />

    </div>
  );
}

export default App;
