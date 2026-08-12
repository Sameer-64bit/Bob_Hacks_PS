import React from 'react';
import type { LectureChapter } from '../types';

interface ChapterFlowchartProps {
  chapters: LectureChapter[];
}

function wrapText(value: string, limit: number): string[] {
  const words = value.split(/\s+/).filter(Boolean);
  const lines: string[] = [];
  let current = '';

  words.forEach((word) => {
    if ((current + ' ' + word).trim().length > limit && current) {
      lines.push(current);
      current = word;
    } else {
      current = `${current} ${word}`.trim();
    }
  });

  if (current) lines.push(current);
  return lines.slice(0, 3);
}

export const ChapterFlowchart: React.FC<ChapterFlowchartProps> = ({ chapters }) => {
  if (!chapters.length) return null;

  const visibleChapters = chapters.slice(0, 6);
  const nodeWidth = 172;
  const gap = 22;
  const width = Math.max(720, visibleChapters.length * nodeWidth + (visibleChapters.length - 1) * gap + 48);

  return (
    <div className="chapter-flowchart-card">
      <div className="chapter-flowchart-heading">
        <span className="chapter-flowchart-dot" />
        <div>
          <h4>Lecture Roadmap</h4>
          <p>Chapter sequence derived from the imported analysis</p>
        </div>
      </div>

      <div className="chapter-flowchart-scroll">
        <svg
          className="chapter-flowchart-svg"
          viewBox={`0 0 ${width} 190`}
          role="img"
          aria-label="Lecture chapter flowchart"
        >
          <defs>
            <marker id="chapter-flowchart-arrow" markerWidth="8" markerHeight="8" refX="7" refY="4" orient="auto">
              <path d="M0,0 L8,4 L0,8 z" fill="#6366f1" />
            </marker>
          </defs>

          {visibleChapters.map((chapter, index) => {
            const x = 24 + index * (nodeWidth + gap);
            const lines = wrapText(chapter.title, 22);
            const timestamp = typeof chapter.timestamp === 'number'
              ? `${Math.floor(chapter.timestamp / 60)}:${String(Math.round(chapter.timestamp % 60)).padStart(2, '0')}`
              : chapter.page
                ? `Page ${chapter.page}`
                : `Step ${index + 1}`;

            return (
              <g key={`${chapter.title}-${index}`}>
                {index < visibleChapters.length - 1 && (
                  <line
                    x1={x + nodeWidth}
                    y1="95"
                    x2={x + nodeWidth + gap - 8}
                    y2="95"
                    stroke="#818cf8"
                    strokeWidth="3"
                    markerEnd="url(#chapter-flowchart-arrow)"
                  />
                )}
                <rect x={x} y="38" width={nodeWidth} height="114" rx="16" fill="#eef2ff" stroke="#6366f1" strokeWidth="2" />
                <circle cx={x + 25} cy="65" r="13" fill="#6366f1" />
                <text x={x + 25} y="70" textAnchor="middle" fill="#fff" fontSize="12" fontWeight="700">{index + 1}</text>
                {lines.map((line, lineIndex) => (
                  <text key={lineIndex} x={x + nodeWidth / 2} y={91 + lineIndex * 16} textAnchor="middle" fill="#312e81" fontSize="13" fontWeight="700">
                    {line}
                  </text>
                ))}
                <text x={x + nodeWidth / 2} y="137" textAnchor="middle" fill="#64748b" fontSize="11" fontFamily="monospace">
                  {timestamp}
                </text>
              </g>
            );
          })}
        </svg>
      </div>

      {chapters.length > visibleChapters.length && (
        <p className="chapter-flowchart-more">+ {chapters.length - visibleChapters.length} more chapters in the source</p>
      )}
    </div>
  );
};
