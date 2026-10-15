/**
 * Self-hosted tenant fonts (the CSP only allows same-origin fonts, so no CDN).
 *
 * Each loader is a dynamic import, so Vite emits a separate chunk (CSS + woff2
 * files) per font and a visitor downloads only the font their club chose; the
 * `unicode-range` subsets in the CSS mean browsers fetch just the glyph ranges
 * they need. Lato ships only 400 and 700. Keys match the backend allowlist (`Tenancy.Branding`).
 *
 * The specifiers must stay literal: Vite cannot bundle template-literal imports of
 * package paths, which would silently ship no font files.
 */
const loaders: Record<string, () => Promise<unknown>> = {
  inter: () =>
    Promise.all([
      import('@fontsource/inter/400.css'),
      import('@fontsource/inter/500.css'),
      import('@fontsource/inter/600.css'),
      import('@fontsource/inter/700.css'),
    ]),
  roboto: () =>
    Promise.all([
      import('@fontsource/roboto/400.css'),
      import('@fontsource/roboto/500.css'),
      import('@fontsource/roboto/600.css'),
      import('@fontsource/roboto/700.css'),
    ]),
  lato: () => Promise.all([import('@fontsource/lato/400.css'), import('@fontsource/lato/700.css')]),
  open_sans: () =>
    Promise.all([
      import('@fontsource/open-sans/400.css'),
      import('@fontsource/open-sans/500.css'),
      import('@fontsource/open-sans/600.css'),
      import('@fontsource/open-sans/700.css'),
    ]),
  montserrat: () =>
    Promise.all([
      import('@fontsource/montserrat/400.css'),
      import('@fontsource/montserrat/500.css'),
      import('@fontsource/montserrat/600.css'),
      import('@fontsource/montserrat/700.css'),
    ]),
  source_sans_pro: () =>
    Promise.all([
      import('@fontsource/source-sans-3/400.css'),
      import('@fontsource/source-sans-3/500.css'),
      import('@fontsource/source-sans-3/600.css'),
      import('@fontsource/source-sans-3/700.css'),
    ]),
};

/** Loads the web font for a stored font key. `system` and unknown keys load nothing. */
export function loadTenantFont(key: string | null | undefined): Promise<unknown> {
  const load = key ? loaders[key] : undefined;
  return load ? load().catch(() => undefined) : Promise.resolve();
}
