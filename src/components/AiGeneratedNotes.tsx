import React from 'react';
import type { AiNoteSection, TargetLanguage } from '../types';
import { RichText } from './RichText';

interface AiGeneratedNotesProps {
  sections: AiNoteSection[];
  targetLang: TargetLanguage;
}

const KIND_LABELS: Record<AiNoteSection['kind'], string> = {
  overview: 'Overview',
  definition: 'Definition',
  comparison: 'Comparison',
  process: 'Process',
  formula: 'Formula',
  example: 'Example',
  checklist: 'Checklist',
  diagram: 'Visual explanation',
  summary: 'Summary',
  custom: 'Study note'
};

export const AiGeneratedNotes: React.FC<AiGeneratedNotesProps> = ({ sections, targetLang }) => (
  <section className="notes-section ai-generated-notes-section space-y-3">
    <div className="notes-section-heading flex items-center gap-2">
      <span className="w-2.5 h-2.5 rounded-full bg-violet-600"></span>
      <div>
        <h3 className="text-base sm:text-lg font-bold font-handwriting text-violet-900 border-b border-violet-200 inline-block">
          AI-Generated Study Notes
        </h3>
        <p className="ai-generated-notes-subtitle">
          Structure selected from the uploaded lecture for {targetLang.toUpperCase()}
        </p>
      </div>
    </div>

    <div className="ai-generated-notes-grid">
      {sections.map((section, index) => (
        <article key={section.id} className={`ai-generated-note-card ai-generated-note-${section.kind}`}>
          <div className="ai-generated-note-heading">
            <span className="ai-generated-note-index">{index + 1}</span>
            <div>
              <span className="ai-generated-note-kind">{KIND_LABELS[section.kind]}</span>
              <h4>{section.title}</h4>
            </div>
          </div>

          {section.body && <RichText text={section.body} className="ai-generated-note-body" />}

          {section.formula && (
            <div className="ai-generated-note-formula">
              <RichText text={section.formula} />
            </div>
          )}

          {section.bullets.length > 0 && (
            <ul className="ai-generated-note-bullets">
              {section.bullets.map((bullet, bulletIndex) => (
                <li key={`${section.id}-bullet-${bulletIndex}`}>
                  <span>✓</span>
                  <RichText text={bullet} as="span" />
                </li>
              ))}
            </ul>
          )}

          {section.diagramDescription && (
            <div className="ai-generated-note-diagram-description">
              <span>Visual cue</span>
              <RichText text={section.diagramDescription} />
            </div>
          )}
        </article>
      ))}
    </div>
  </section>
);
