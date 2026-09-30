export interface ThemeTokens {
  primaryColor: string;
  primaryForegroundColor: string;
  secondaryColor: string;
  secondaryForegroundColor: string;
  accentColor: string;
  accentForegroundColor: string;
  backgroundColor: string;
  surfaceColor: string;
  textColor: string;
  mutedColor: string;
  mutedForegroundColor: string;
  borderColor: string;
  dangerColor: string;
  dangerForegroundColor: string;
  radius: string;
  fontFamily: string;
}

export const platformTheme: ThemeTokens = {
  primaryColor: '#0f172a',
  primaryForegroundColor: '#f8fafc',
  secondaryColor: '#1e293b',
  secondaryForegroundColor: '#f8fafc',
  accentColor: '#0ea5e9',
  accentForegroundColor: '#f8fafc',
  backgroundColor: '#f8fafc',
  surfaceColor: '#ffffff',
  textColor: '#0f172a',
  mutedColor: '#e2e8f0',
  mutedForegroundColor: '#64748b',
  borderColor: '#cbd5e1',
  dangerColor: '#dc2626',
  dangerForegroundColor: '#fef2f2',
  radius: '0.75rem',
  fontFamily: 'ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif',
};

export const neutralTheme: ThemeTokens = {
  ...platformTheme,
  primaryColor: '#334155',
  accentColor: '#334155',
};

export const tenantThemeA: ThemeTokens = {
  ...platformTheme,
  primaryColor: '#15803d',
  secondaryColor: '#166534',
  accentColor: '#f59e0b',
  secondaryForegroundColor: '#f0fdf4',
};

export const tenantThemeB: ThemeTokens = {
  ...platformTheme,
  primaryColor: '#7c3aed',
  accentColor: '#db2777',
  secondaryColor: '#4c1d95',
};

const CSS_VAR_MAP: Record<keyof ThemeTokens, string> = {
  primaryColor: '--color-primary',
  primaryForegroundColor: '--color-primary-foreground',
  secondaryColor: '--color-secondary',
  secondaryForegroundColor: '--color-secondary-foreground',
  accentColor: '--color-accent',
  accentForegroundColor: '--color-accent-foreground',
  backgroundColor: '--color-background',
  surfaceColor: '--color-surface',
  textColor: '--color-text',
  mutedColor: '--color-muted',
  mutedForegroundColor: '--color-muted-foreground',
  borderColor: '--color-border',
  dangerColor: '--color-danger',
  dangerForegroundColor: '--color-danger-foreground',
  radius: '--radius',
  fontFamily: '--font-family',
};

export function themeToCssVariables(theme: ThemeTokens): Record<string, string> {
  return Object.entries(CSS_VAR_MAP).reduce<Record<string, string>>((acc, [token, cssVar]) => {
    acc[cssVar] = theme[token as keyof ThemeTokens];
    return acc;
  }, {});
}

export interface ApplyThemeTarget {
  documentElement: { style: { setProperty(name: string, value: string): void } };
}

export function applyTheme(theme: ThemeTokens, target?: ApplyThemeTarget): void {
  const root =
    target ??
    (typeof document !== 'undefined' ? (document as unknown as ApplyThemeTarget) : undefined);
  if (!root) return;
  const vars = themeToCssVariables(theme);
  for (const [name, value] of Object.entries(vars)) {
    root.documentElement.style.setProperty(name, value);
  }
}
