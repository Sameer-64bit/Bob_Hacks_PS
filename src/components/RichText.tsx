import React from 'react';
import katex from 'katex';

interface RichTextProps {
  text: string;
  className?: string;
  as?: 'div' | 'span';
}

const MATH_TOKEN = /(\$\$[\s\S]*?\$\$|\$[^$\n]+\$|\\\([\s\S]*?\\\)|\\\[[\s\S]*?\\\])/g;

function renderMathToken(token: string): { expression: string; displayMode: boolean } {
  if (token.startsWith('$$')) return { expression: token.slice(2, -2), displayMode: true };
  if (token.startsWith('\\[')) return { expression: token.slice(2, -2), displayMode: true };
  if (token.startsWith('\\(')) return { expression: token.slice(2, -2), displayMode: false };
  return { expression: token.slice(1, -1), displayMode: false };
}

export const RichText: React.FC<RichTextProps> = ({ text, className = '', as = 'div' }) => {
  const Tag = as;
  const tokens = text.split(MATH_TOKEN);

  return (
    <Tag className={`rich-text ${className}`.trim()}>
      {tokens.map((token, index) => {
        if (!token) return null;

        if (token.startsWith('$') || token.startsWith('\\(') || token.startsWith('\\[')) {
          const { expression, displayMode } = renderMathToken(token);
          try {
            return (
              <span
                key={`math-${index}`}
                className={displayMode ? 'rich-text-math-display' : 'rich-text-math-inline'}
                dangerouslySetInnerHTML={{
                  __html: katex.renderToString(expression, {
                    displayMode,
                    throwOnError: false
                  })
                }}
              />
            );
          } catch {
            return <span key={`math-fallback-${index}`}>{token}</span>;
          }
        }

        return (
          <React.Fragment key={`text-${index}`}>
            {token.split('\n').map((line, lineIndex, lines) => (
              <React.Fragment key={`line-${lineIndex}`}>
                {line}
                {lineIndex < lines.length - 1 && <br />}
              </React.Fragment>
            ))}
          </React.Fragment>
        );
      })}
    </Tag>
  );
};
