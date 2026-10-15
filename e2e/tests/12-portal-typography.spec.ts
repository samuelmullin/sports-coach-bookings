import { expect, test } from '@playwright/test';

test.describe('portal typography', () => {
  // Regression: the tenant's stored font key ("inter") was used as the CSS family and
  // no font file was ever served, so the portal rendered in the browser's serif.
  test('serves and applies the tenant font from the same origin', async ({ page }) => {
    const fontRequests: string[] = [];
    const violations: string[] = [];
    page.on('response', (response) => {
      if (/\.woff2(\?|$)/.test(response.url())) fontRequests.push(response.url());
    });
    page.on('console', (message) => {
      if (/content security policy/i.test(message.text())) violations.push(message.text());
    });

    await page.goto('/');
    await expect(page.getByRole('main')).toBeVisible();

    await expect.poll(() => fontRequests.length, { message: 'a font file was downloaded' }).toBeGreaterThan(0);
    for (const url of fontRequests) expect(new URL(url).origin).toBe(new URL(page.url()).origin);

    await expect
      .poll(() => page.evaluate(() => document.fonts.check('16px Inter')), {
        message: 'Inter is loaded in the document',
      })
      .toBe(true);

    const family = await page.evaluate(() => getComputedStyle(document.body).fontFamily);
    expect(family).toMatch(/^"?Inter"?,/);
    expect(family).toMatch(/sans-serif$/);
    expect(violations).toEqual([]);
  });
});
