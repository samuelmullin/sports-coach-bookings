import type { ReactNode } from 'react';

function renderInline(text: string, keyPrefix: string): ReactNode[] {
  const nodes: ReactNode[] = [];
  const pattern = /(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`)/g;
  let lastIndex = 0;
  let match: RegExpExecArray | null;
  let index = 0;
  while ((match = pattern.exec(text)) !== null) {
    if (match.index > lastIndex) nodes.push(text.slice(lastIndex, match.index));
    const token = match[0];
    const key = `${keyPrefix}-${index++}`;
    if (token.startsWith('**')) {
      nodes.push(<strong key={key}>{token.slice(2, -2)}</strong>);
    } else if (token.startsWith('`')) {
      nodes.push(
        <code key={key} className="rounded bg-muted px-1 py-0.5 text-xs">
          {token.slice(1, -1)}
        </code>,
      );
    } else {
      nodes.push(<em key={key}>{token.slice(1, -1)}</em>);
    }
    lastIndex = match.index + token.length;
  }
  if (lastIndex < text.length) nodes.push(text.slice(lastIndex));
  return nodes;
}

/** Minimal, dependency-free markdown preview (headings, lists, bold/italic/code). */
export function MarkdownPreview({ markdown }: { markdown: string }) {
  const lines = markdown.split('\n');
  const blocks: ReactNode[] = [];
  let list: string[] = [];

  const flushList = () => {
    if (list.length === 0) return;
    blocks.push(
      <ul key={`ul-${blocks.length}`} className="ml-5 list-disc space-y-1 text-sm">
        {list.map((item, index) => (
          <li key={index}>{renderInline(item, `li-${blocks.length}-${index}`)}</li>
        ))}
      </ul>,
    );
    list = [];
  };

  lines.forEach((line, index) => {
    const key = `b-${index}`;
    if (/^\s*[-*]\s+/.test(line)) {
      list.push(line.replace(/^\s*[-*]\s+/, ''));
      return;
    }
    flushList();
    if (line.startsWith('### ')) {
      blocks.push(
        <h4 key={key} className="text-sm font-semibold">
          {renderInline(line.slice(4), key)}
        </h4>,
      );
    } else if (line.startsWith('## ')) {
      blocks.push(
        <h3 key={key} className="text-base font-semibold">
          {renderInline(line.slice(3), key)}
        </h3>,
      );
    } else if (line.startsWith('# ')) {
      blocks.push(
        <h2 key={key} className="text-lg font-semibold">
          {renderInline(line.slice(2), key)}
        </h2>,
      );
    } else if (line.trim() === '') {
      blocks.push(<div key={key} className="h-2" />);
    } else {
      blocks.push(
        <p key={key} className="text-sm">
          {renderInline(line, key)}
        </p>,
      );
    }
  });
  flushList();

  return (
    <div className="flex flex-col gap-2" data-testid="markdown-preview">
      {blocks}
    </div>
  );
}
