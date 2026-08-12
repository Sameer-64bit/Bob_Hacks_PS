import React from 'react';
import type { DiagramSnippet, TargetLanguage } from '../types';
import { getLanguageInfo } from '../types';
import { Network, CheckCircle2, ArrowRight, Lightbulb } from 'lucide-react';

interface DiagramComparisonProps {
  diagrams: DiagramSnippet[];
  targetLang: TargetLanguage;
}

export const DiagramComparison: React.FC<DiagramComparisonProps> = ({
  diagrams,
  targetLang
}) => {
  if (!diagrams || diagrams.length === 0) return null;

  const langInfo = getLanguageInfo(targetLang);

  return (
    <div className="bg-white border border-slate-200 rounded-2xl p-4 lg:p-6 shadow-sm space-y-6">
      
      {/* Header */}
      <div className="flex items-center justify-between border-b border-slate-200 pb-3.5">
        <div className="flex items-center gap-2.5">
          <div className="p-2 rounded-xl bg-purple-50 text-purple-700 border border-purple-200">
            <Network className="w-5 h-5" />
          </div>
          <div>
            <h3 className="text-sm font-bold text-slate-900 flex items-center gap-2">
              <span>AI Vision Diagram & Graph Enhancer</span>
              <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-purple-100 text-purple-800 border border-purple-200">
                Vector Matcher
              </span>
            </h3>
            <p className="text-xs text-slate-500">
              Comparing rough hand-drawn board sketch to clean vector graphics
            </p>
          </div>
        </div>
      </div>

      {/* Diagram Items */}
      {diagrams.map((diag) => {
        const explanation = diag.explanations[targetLang] || diag.explanations.en;
        const takeaways = diag.keyTakeaways[targetLang] || diag.keyTakeaways.en;

        return (
          <div key={diag.id} className="bg-slate-50 rounded-2xl border border-slate-200 p-4 lg:p-5 space-y-5 shadow-sm">
            
            <div className="flex items-center justify-between">
              <h4 className="text-xs font-bold text-slate-900 flex items-center gap-2">
                <span className="w-2.5 h-2.5 rounded-full bg-blue-600"></span>
                {diag.title}
              </h4>
              <span className="text-[10px] font-mono font-bold uppercase px-2.5 py-0.5 rounded-md bg-white text-blue-700 border border-slate-200 shadow-sm">
                Category: {diag.type}
              </span>
            </div>

            {/* Side-by-Side Comparison Grid */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 items-center">
              
              {/* Left: Original Whiteboard Sketch */}
              <div className="bg-white rounded-xl p-3 border border-slate-200 space-y-2 flex flex-col items-center shadow-sm">
                <div className="w-full flex items-center justify-between border-b border-slate-200 pb-2">
                  <span className="text-xs font-bold text-rose-600 flex items-center gap-1.5">
                    ✏️ Teacher Board Drawing
                  </span>
                  <span className="text-[10px] text-slate-400 font-mono">Whiteboard Raw</span>
                </div>
                <div
                  className="diagram-preview-frame"
                  dangerouslySetInnerHTML={{ __html: diag.roughSketchSvg }}
                />
              </div>

              {/* Right: AI Clean Vector Match */}
              <div className="bg-white rounded-xl p-3 border border-blue-200 space-y-2 flex flex-col items-center shadow-sm">
                <div className="w-full flex items-center justify-between border-b border-slate-200 pb-2">
                  <span className="text-xs font-bold text-emerald-600 flex items-center gap-1.5">
                    <CheckCircle2 className="w-3.5 h-3.5" />
                    AI Vector Clean Match
                  </span>
                  <span className="text-[10px] font-bold bg-blue-100 text-blue-800 font-mono px-1.5 py-0.5 rounded">High Res</span>
                </div>
                <div
                  className="diagram-preview-frame"
                  dangerouslySetInnerHTML={{ __html: diag.cleanDiagramSvg }}
                />
              </div>

            </div>

            {/* Explanation & Key Takeaways */}
            <div className="grid grid-cols-1 lg:grid-cols-12 gap-4 pt-2 border-t border-slate-200">
              
              {/* Custom Explanation */}
              <div className="lg:col-span-7 bg-amber-50/90 rounded-xl p-3.5 border border-amber-200 space-y-2">
                <div className="flex items-center gap-1.5 text-xs font-bold text-amber-900">
                  <Lightbulb className="w-4 h-4 text-amber-600" />
                  <span>Diagram Concept Breakdown ({langInfo.nativeName})</span>
                </div>
                <p
                  dir={langInfo.dir}
                  className="text-xs text-amber-950 leading-relaxed font-medium"
                  style={{ fontFamily: langInfo.fontFamily }}
                >
                  {explanation}
                </p>
              </div>

              {/* Key Takeaways */}
              <div className="lg:col-span-5 bg-white rounded-xl p-3.5 border border-slate-200 space-y-2 shadow-sm">
                <div className="flex items-center gap-1.5 text-xs font-bold text-blue-700">
                  <ArrowRight className="w-4 h-4" />
                  <span>Key Visual Takeaways</span>
                </div>
                <ul
                  dir={langInfo.dir}
                  className="space-y-1.5 text-xs text-slate-800 font-medium"
                  style={{ fontFamily: langInfo.fontFamily }}
                >
                  {takeaways.map((item, idx) => (
                    <li key={idx} className="flex items-start gap-2">
                      <span className="text-emerald-600 font-bold">•</span>
                      <span>{item}</span>
                    </li>
                  ))}
                </ul>
              </div>

            </div>

          </div>
        );
      })}

    </div>
  );
};
