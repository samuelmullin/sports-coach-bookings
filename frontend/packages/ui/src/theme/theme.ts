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

/**
 * The fonts a tenant may choose. Keys mirror the backend allowlist
 * (`Tenancy.Branding`); the value is a full CSS stack that always ends in a
 * generic family so a font that is not installed falls back to sans-serif
 * instead of the browser default (serif).
 */
export const FONT_STACKS: Record<string, { label: string; stack: string }> = {
  inter: {
    label: 'Inter',
    stack: 'Inter, ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif',
  },
  roboto: {
    label: 'Roboto',
    stack: 'Roboto, ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif',
  },
  lato: {
    label: 'Lato',
    stack: 'Lato, ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif',
  },
  open_sans: {
    label: 'Open Sans',
    stack: '"Open Sans", ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif',
  },
  montserrat: {
    label: 'Montserrat',
    stack: 'Montserrat, ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif',
  },
  source_sans_pro: {
    label: 'Source Sans Pro',
    stack:
      '"Source Sans Pro", ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif',
  },
  system: {
    label: 'System default',
    stack: 'ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif',
  },
};

/** The `{ value, label }` options for a font picker. */
export const FONT_OPTIONS = Object.entries(FONT_STACKS).map(([value, { label }]) => ({
  value,
  label,
}));

/** CSS font stack for a stored font key; unknown or empty values use the platform stack. */
export function fontStack(key: string | null | undefined): string {
  return (key && FONT_STACKS[key]?.stack) || platformTheme.fontFamily;
}

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
