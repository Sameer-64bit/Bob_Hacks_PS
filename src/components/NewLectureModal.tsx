import React, { useEffect, useState, useRef } from 'react';
import type { Lecture, TargetLanguage, WhiteboardPage } from '../types';
import { processNewBoardImageAndTranscript } from '../services/aiService';
import { isAnalysisDocument, parseAnalysisDocument, type AnalysisDocument } from '../services/analysisDocument';
import { generateLectureFromInputs, generateLectureFromPdf } from '../services/notesPipeline';
import { X, Upload, Sparkles, Image as ImageIcon, FileText, CheckCircle, Loader2 } from 'lucide-react';

interface NewLectureModalProps {
  isOpen: boolean;
  onClose: () => void;
  onAddPage: (page: WhiteboardPage) => void;
  onImportLecture: (lecture: Lecture) => void;
  currentLang: TargetLanguage;
  mode?: 'lecture' | 'pdf';
}

export const NewLectureModal: React.FC<NewLectureModalProps> = ({
  isOpen,
  onClose,
  onAddPage,
  onImportLecture,
  currentLang,
  mode = 'lecture'
}) => {
  const pdfOnly = mode === 'pdf';
  const [transcriptText, setTranscriptText] = useState('');
  const [uploadedImageDataUrl, setUploadedImageDataUrl] = useState<string>('');
  const [fileName, setFileName] = useState<string>('');
  const [presentationFile, setPresentationFile] = useState<File | null>(null);
  const [presentationFileName, setPresentationFileName] = useState<string>('');
  const [loading, setLoading] = useState(false);
  const [success, setSuccess] = useState(false);
  const [analysisDocument, setAnalysisDocument] = useState<AnalysisDocument | null>(null);
  const [errorMessage, setErrorMessage] = useState('');
  const [pipelineMessage, setPipelineMessage] = useState('');

  const fileInputRef = useRef<HTMLInputElement>(null);
  const presentationInputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!isOpen) return;
    setTranscriptText('');
    setUploadedImageDataUrl('');
    setFileName('');
    setPresentationFile(null);
    setPresentationFileName('');
    setLoading(false);
    setSuccess(false);
    setAnalysisDocument(null);
    setErrorMessage('');
    setPipelineMessage('');
  }, [isOpen, mode]);

  if (!isOpen) return null;

  // Handle local file selection from device
  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setFileName(file.name);
    setErrorMessage('');
    setPipelineMessage('');
    e.currentTarget.value = '';
    const reader = new FileReader();

    if (file.type === 'application/json' || file.name.toLowerCase().endsWith('.json')) {
      reader.onload = (event) => {
        try {
          const parsed = parseAnalysisDocument(String(event.target?.result || ''));
          if (!isAnalysisDocument(parsed)) {
            throw new Error('This JSON does not match the lecture analysis format.');
          }

          setAnalysisDocument(parsed);
          setUploadedImageDataUrl('');
          setTranscriptText('');
        } catch (error) {
          setAnalysisDocument(null);
          setFileName('');
          setErrorMessage(error instanceof Error ? error.message : 'Unable to read the analysis JSON.');
        }
      };
      reader.readAsText(file);
      return;
    }

    setAnalysisDocument(null);
    if (file.type === 'image/svg+xml' || file.name.endsWith('.svg')) {
      reader.onload = (event) => {
        const svgText = event.target?.result as string;
        setUploadedImageDataUrl(svgText);
      };
      reader.readAsText(file);
    } else {
      reader.onload = (event) => {
        const dataUrl = event.target?.result as string;
        setUploadedImageDataUrl(dataUrl);
      };
      reader.readAsDataURL(file);
    }
  };

  const handlePresentationChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    e.currentTarget.value = '';
    setErrorMessage('');
    setPipelineMessage('');

    const lowerName = file.name.toLowerCase();
    if (pdfOnly && !lowerName.endsWith('.pdf')) {
      setPresentationFile(null);
      setPresentationFileName('');
      setErrorMessage('This Smartboard upload accepts PDF slides only.');
      return;
    }

    if (!pdfOnly && !lowerName.endsWith('.pptx') && !lowerName.endsWith('.pdf')) {
      setPresentationFile(null);
      setPresentationFileName('');
      setErrorMessage('Please select a .pptx or .pdf lecture presentation. Convert legacy .ppt files to .pptx first.');
      return;
    }

    setPresentationFile(file);
    setPresentationFileName(file.name);
  };

  const handleProcess = async () => {
    setLoading(true);
    setSuccess(false);
    setErrorMessage('');

    try {
      if (pdfOnly) {
        if (!presentationFile) throw new Error('Select a PDF lecture before generating notes.');

        const result = await generateLectureFromPdf(
          presentationFile,
          currentLang,
          setPipelineMessage
        );
        if (!result.aiGenerated) {
          throw new Error(`Gemini could not generate AI notes for this PDF. ${result.message || ''}`.trim());
        }
        onImportLecture(result.lecture);
        setPipelineMessage(result.message || 'PDF slides analyzed by AI.');
        setSuccess(true);
        setTimeout(() => {
          setLoading(false);
          setSuccess(false);
          onClose();
        }, 1000);
        return;
      }

      if (analysisDocument) {
        const result = await generateLectureFromInputs(analysisDocument, currentLang, presentationFile);
        onImportLecture(result.lecture);
        setPipelineMessage(result.message || 'Lecture imported.');
        setSuccess(true);
        setTimeout(() => {
          setLoading(false);
          setSuccess(false);
          onClose();
        }, 1000);
        return;
      }

      const result = await processNewBoardImageAndTranscript(
        uploadedImageDataUrl || '',
        transcriptText,
        currentLang
      );

      onAddPage(result.page);
      setSuccess(true);
      setTimeout(() => {
        setLoading(false);
        setSuccess(false);
        onClose();
      }, 1000);
    } catch (err) {
      console.error(err);
      setErrorMessage(err instanceof Error ? err.message : 'Unable to process this file.');
      setLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 bg-slate-950/80 backdrop-blur-md flex items-center justify-center p-4">
      <div className="bg-slate-900 border border-slate-800 rounded-2xl max-w-xl w-full p-6 shadow-2xl space-y-5 animate-in fade-in zoom-in duration-200">
        
        {/* Header */}
        <div className="flex items-center justify-between border-b border-slate-800 pb-3.5">
          <div className="flex items-center gap-2.5">
            <div className="p-2 rounded-xl bg-cyan-500/10 text-cyan-400 border border-cyan-500/20">
              <Upload className="w-5 h-5" />
            </div>
            <div>
              <h3 className="text-base font-bold text-slate-100">
                {pdfOnly ? 'Upload PDF Slides for AI Notes' : 'Upload Lecture JSON + Presentation'}
              </h3>
              <p className="text-xs text-slate-400">
                {pdfOnly
                  ? 'PDF only • OCR reads each page, then Gemini writes the explanations and handwritten notes'
                  : 'JSON supplies lecture facts; PPTX or PDF supplies the actual lecture slides'}
              </p>
            </div>
          </div>

          <button
            onClick={onClose}
            className="p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 transition-colors"
          >
            <X className="w-5 h-5" />
          </button>
        </div>

        {/* Input Form */}
        <div className="space-y-4">
          
          {/* Upload Slide from Device File Input */}
          <div className="space-y-1.5">
            <input
              type="file"
              id={pdfOnly ? 'smartboard-pdf-upload' : 'analysis-json-upload'}
              ref={pdfOnly ? presentationInputRef : fileInputRef}
              accept={pdfOnly
                ? '.pdf,application/pdf'
                : 'application/json,.json,image/*,.svg'}
              onChange={pdfOnly ? handlePresentationChange : handleFileChange}
              className="hidden"
            />

            {!pdfOnly && (
              <>
                <label className="text-xs font-semibold text-slate-300 flex items-center gap-1.5">
                  <ImageIcon className="w-4 h-4 text-cyan-400" />
                  <span>Select Analysis JSON</span>
                </label>

                <div
                  onClick={() => fileInputRef.current?.click()}
                  className="border-2 border-dashed border-slate-700 hover:border-cyan-500/60 rounded-xl p-5 bg-slate-950 text-center space-y-2 cursor-pointer transition-all hover:bg-slate-900/50 group"
                >
                  <Upload className="w-7 h-7 text-cyan-400 mx-auto group-hover:scale-110 transition-transform" />
                  {fileName ? (
                    <div className="space-y-1">
                      <p className="text-xs font-bold text-emerald-400">Selected File: {fileName}</p>
                      <p className="text-[11px] text-slate-500">Click to change file</p>
                    </div>
                  ) : (
                    <div className="space-y-1">
                      <p className="text-xs font-semibold text-slate-200">Click to browse the lecture analysis JSON</p>
                      <p className="text-[11px] text-slate-500">This JSON supplies summaries, sections, timestamps and transcript.</p>
                    </div>
                  )}
                </div>
              </>
            )}

            {pdfOnly && (
              <button
                type="button"
                onClick={() => presentationInputRef.current?.click()}
                className="w-full border-2 border-dashed border-cyan-700/70 hover:border-cyan-400 rounded-xl p-5 bg-cyan-950/20 text-center transition-colors"
              >
                <Upload className="w-7 h-7 text-cyan-300 mx-auto mb-2" />
                <span className="text-xs font-semibold text-cyan-100 block">
                  {presentationFileName ? `PDF selected: ${presentationFileName}` : 'Click to upload PDF slides'}
                </span>
                <span className="text-[11px] text-slate-400 block mt-1">
                  Only .pdf files are accepted. OCR will read scanned pages automatically.
                </span>
              </button>
            )}

            {!pdfOnly && <input
              type="file"
              ref={presentationInputRef}
              accept=".pptx,.pdf,application/vnd.openxmlformats-officedocument.presentationml.presentation,application/pdf"
              onChange={handlePresentationChange}
              className="hidden"
            />}

            {!pdfOnly && <button
              type="button"
              onClick={() => presentationInputRef.current?.click()}
              className="w-full border border-dashed border-cyan-700/70 hover:border-cyan-400 rounded-xl p-3 bg-cyan-950/20 text-left transition-colors"
            >
              <span className="text-xs font-semibold text-cyan-200 block">
                {presentationFileName ? `Presentation selected: ${presentationFileName}` : 'Add the lecture PPTX or PDF'}
              </span>
              <span className="text-[11px] text-slate-500 block mt-1">
                PPTX slide text or PDF page text/images are merged with matching JSON sections.
              </span>
            </button>}

            {/* Slide Image Preview if loaded */}
            {(uploadedImageDataUrl || analysisDocument || (pdfOnly && presentationFileName)) && (
              <div className="bg-slate-950 p-2 rounded-xl border border-slate-800 flex items-center gap-3">
                {pdfOnly ? (
                  <div className="w-16 h-12 flex items-center justify-center overflow-hidden border border-slate-800 rounded bg-slate-900 text-rose-300 text-[10px] font-bold text-center">
                    PDF
                  </div>
                ) : analysisDocument ? (
                  <div className="w-16 h-12 flex items-center justify-center overflow-hidden border border-slate-800 rounded bg-slate-900 text-cyan-300 text-[10px] font-bold text-center">
                    JSON
                  </div>
                ) : uploadedImageDataUrl.startsWith('<svg') ? (
                  <div
                    className="w-16 h-12 flex items-center justify-center overflow-hidden border border-slate-800 rounded bg-slate-900"
                    dangerouslySetInnerHTML={{ __html: uploadedImageDataUrl }}
                  />
                ) : (
                  <img src={uploadedImageDataUrl} alt="Slide Preview" className="w-16 h-12 object-cover rounded border border-slate-800" />
                )}
                <div className="text-xs space-y-0.5">
                  <span className="font-bold text-cyan-400 block">
                    {pdfOnly ? 'PDF Slides Loaded' : analysisDocument ? 'Analysis JSON Loaded' : 'Slide Preview Loaded'}
                  </span>
                  <span className="text-[11px] text-slate-400">
                    {pdfOnly
                      ? 'Pages will be OCR-read and analyzed by Gemini.'
                      : analysisDocument
                        ? `${presentationFileName ? 'JSON + presentation loaded.' : 'JSON loaded.'} Notes will use the uploaded content.`
                        : 'Ready for slide processing.'}
                  </span>
                </div>
              </div>
            )}

            {pipelineMessage && (
              <p className="text-[11px] text-amber-200 bg-amber-950/30 border border-amber-800 rounded-lg p-2">
                {pipelineMessage}
              </p>
            )}

            {errorMessage && (
              <p className="text-[11px] text-rose-300 bg-rose-950/40 border border-rose-800 rounded-lg p-2">
                {errorMessage}
              </p>
            )}
          </div>

          {/* Teacher Speech Transcript Input */}
          {!pdfOnly && <div className="space-y-1.5">
            <label className="text-xs font-semibold text-slate-300 flex items-center gap-1.5">
              <FileText className="w-4 h-4 text-emerald-400" />
              <span>{analysisDocument ? 'Transcript supplied by JSON' : 'Teacher Speech Transcript'}</span>
            </label>
            <textarea
              rows={3}
              value={transcriptText}
              onChange={(e) => setTranscriptText(e.target.value)}
              className="w-full bg-slate-950 border border-slate-800 rounded-xl p-3 text-xs text-slate-200 focus:outline-none focus:border-cyan-500/50 resize-none font-mono"
              placeholder={analysisDocument ? 'Transcript is read from the imported JSON.' : 'Paste raw speech transcript here...'}
              disabled={Boolean(analysisDocument)}
            />
          </div>}

        </div>

        {/* Action Buttons */}
        <div className="flex items-center justify-end gap-3 border-t border-slate-800 pt-3.5">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 rounded-xl text-xs font-semibold text-slate-400 hover:text-slate-200 transition-colors"
          >
            Cancel
          </button>
          
          <button
            type="button"
            disabled={loading || (pdfOnly ? !presentationFile : (!transcriptText.trim() && !analysisDocument))}
            onClick={handleProcess}
            className="flex items-center gap-2 bg-gradient-to-r from-cyan-500 to-blue-600 hover:from-cyan-400 hover:to-blue-500 text-slate-950 font-bold px-5 py-2 rounded-xl text-xs shadow-lg shadow-cyan-500/20 disabled:opacity-40 transition-all"
          >
            {loading ? (
              <>
                <Loader2 className="w-4 h-4 animate-spin" />
                <span>{pdfOnly ? 'OCR + Gemini are generating notes...' : 'Reading JSON + presentation and generating notes...'}</span>
              </>
            ) : success ? (
              <>
                <CheckCircle className="w-4 h-4 text-slate-950" />
                <span>{pdfOnly || analysisDocument ? 'Lecture Imported' : 'Success! Slide Ingested'}</span>
              </>
            ) : (
              <>
                <Sparkles className="w-4 h-4" />
                <span>{pdfOnly ? 'Run OCR & Generate AI Notes' : analysisDocument ? 'Generate Notes from JSON + Presentation' : 'Process & Extract Notes'}</span>
              </>
            )}
          </button>
        </div>

      </div>
    </div>
  );
};
