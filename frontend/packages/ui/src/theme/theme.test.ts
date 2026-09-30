import { describe, expect, it } from 'vitest';
import { applyTheme, neutralTheme, themeToCssVariables, tenantThemeA, tenantThemeB } from './theme';

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
