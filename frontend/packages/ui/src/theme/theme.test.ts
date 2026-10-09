import { describe, expect, it } from 'vitest';
import {
  FONT_OPTIONS,
  applyTheme,
  fontStack,
  neutralTheme,
  platformTheme,
  themeToCssVariables,
  tenantThemeA,
  tenantThemeB,
} from './theme';

describe('theme', () => {
  it('maps tokens to css variables', () => {
    const vars = themeToCssVariables(tenantThemeA);
    expect(vars['--color-primary']).toBe('#15803d');
    expect(vars['--color-accent']).toBe('#f59e0b');
    expect(vars['--radius']).toBe('0.75rem');
  });

  it('applies variables to the document root', () => {
    const applied = new Map<string, string>();
    const target = {
      documentElement: {
        style: {
          setProperty: (name: string, value: string) => {
            applied.set(name, value);
          },
        },
      },
    };
    applyTheme(tenantThemeB, target);
    expect(applied.get('--color-primary')).toBe('#7c3aed');
  });

  it('ships a neutral theme for the splash state', () => {
    expect(neutralTheme.primaryColor).toBeTruthy();
  });
});

// Regression: the portal applied the stored key ("inter") as the CSS font-family,
// so no font matched and the browser fell back to its default serif.
describe('fontStack', () => {
  it('maps every allowed key to a stack ending in a generic sans-serif family', () => {
    for (const { value } of FONT_OPTIONS) {
      expect(fontStack(value)).toMatch(/sans-serif$/);
    }
    expect(fontStack('open_sans')).toContain('"Open Sans"');
  });

  it('never returns a bare key, and falls back to the platform stack', () => {
    expect(fontStack('inter')).not.toBe('inter');
    expect(fontStack(undefined)).toBe(platformTheme.fontFamily);
    expect(fontStack('not-a-font')).toBe(platformTheme.fontFamily);
  });

  it('offers exactly the fonts the backend allows', () => {
    expect(FONT_OPTIONS.map((o) => o.value).sort()).toEqual(
      ['inter', 'roboto', 'lato', 'open_sans', 'montserrat', 'source_sans_pro', 'system'].sort(),
    );
  });
});
