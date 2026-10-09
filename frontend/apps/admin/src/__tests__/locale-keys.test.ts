import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import en from '../locales/en';

// Regression: `t('nav.account')` and `t('nav.myAccount')` shipped with no English
// string, so the raw key was rendered in the header. Every literal translation key
// used in the source must resolve.
const SRC = join(__dirname, '..');

function sourceFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return name === '__tests__' ? [] : sourceFiles(path);
    return /\.(ts|tsx)$/.test(name) && !name.endsWith('.test.tsx') ? [path] : [];
  });
}

function resolve(key: string): unknown {
  return key
    .split('.')
    .reduce<unknown>((node, part) => (node as Record<string, unknown> | undefined)?.[part], en);
}

describe('translation keys', () => {
  it('every literal t("…") key used in the app exists in the English locale', () => {
    const missing: string[] = [];
    for (const file of sourceFiles(SRC)) {
      const text = readFileSync(file, 'utf8');
      for (const match of text.matchAll(/\bt\(\s*'([A-Za-z][\w]*(?:\.[\w]+)+)'/g)) {
        // i18next stores plurals as `key_one` / `key_other`.
        const found = [match[1], `${match[1]}_one`, `${match[1]}_other`].some(
          (key) => typeof resolve(key) === 'string',
        );
        if (!found) {
          missing.push(`${match[1]}  (${file.replace(SRC, 'src')})`);
        }
      }
    }
    expect(missing).toEqual([]);
  });
});
