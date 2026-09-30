import type { ReactNode } from 'react';

/**
 * Minimal, dependency-free Markdown renderer for waiver bodies.
 * Renders a safe subset: headings, paragraphs, bullet lists and bold text.
 */
function renderInline(text: string, keyPrefix: string): ReactNode[] {
  const parts = text.split(/(\*\*[^*]+\*\*)/g).filter(Boolean);
  return parts.map((part, index) =>
    part.startsWith('**') && part.endsWith('**') ? (
      <strong key={`${keyPrefix}-${index}`}>{part.slice(2, -2)}</strong>
    ) : (
      <span key={`${keyPrefix}-${index}`}>{part}</span>
    ),
  );
}

export function Markdown({ content, className }: { content: string; className?: string }) {
  const lines = content.replace(/\r\n/g, '\n').split('\n');
  const blocks: ReactNode[] = [];
  let list: string[] = [];
  let paragraph: string[] = [];

  const flushList = (key: string) => {
    if (list.length === 0) return;
    blocks.push(
      <ul key={key} className="ml-5 list-disc">
        {list.map((item, index) => (
          <li key={`${key}-${index}`}>{renderInline(item, `${key}-${index}`)}</li>
        ))}
      </ul>,
    );
    list = [];
  };

  const flushParagraph = (key: string) => {
    if (paragraph.length === 0) return;
    blocks.push(<p key={key}>{renderInline(paragraph.join(' '), key)}</p>);
    paragraph = [];
  };

  lines.forEach((line, index) => {
    const trimmed = line.trim();
    const key = `block-${index}`;
    if (trimmed === '') {
      flushList(`${key}-list`);
      flushParagraph(`${key}-p`);
      return;
    }
    const heading = /^(#{1,6})\s+(.*)$/.exec(trimmed);
    if (heading) {
      flushList(`${key}-list`);
      flushParagraph(`${key}-p`);
      const level = Math.min(heading[1].length, 3);
      const Tag = `h${level + 2}` as 'h3' | 'h4' | 'h5';
      blocks.push(
        <Tag key={key} className="font-semibold">
          {renderInline(heading[2], key)}
        </Tag>,
      );
      return;
    }
    const bullet = /^[-*]\s+(.*)$/.exec(trimmed);
    if (bullet) {
      flushParagraph(`${key}-p`);
      list.push(bullet[1]);
      return;
    }
    paragraph.push(trimmed);
  });
  flushList('final-list');
  flushParagraph('final-p');

  return <div className={className}>{blocks}</div>;
}
