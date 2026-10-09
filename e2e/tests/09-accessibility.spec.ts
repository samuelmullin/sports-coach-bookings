import AxeBuilder from '@axe-core/playwright';
import type { Page } from '@playwright/test';
import { expect, test } from './fixtures';
import { SEEDED, loginAdmin } from './helpers';

async function expectAccessible(page: Page, label: string) {
  await expect(page.getByTestId('scb-splash')).toBeHidden();

  const results = await new AxeBuilder({ page })
    .withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa'])
    .analyze();

  expect(
    results.violations.map((violation) => ({
      id: violation.id,
      impact: violation.impact,
      help: violation.help,
      nodes: violation.nodes.map((node) => ({
        target: node.target.join(' '),
        html: node.html,
        failureSummary: node.failureSummary,
      })),
    })),
    `${label} has automated accessibility violations`,
  ).toEqual([]);
}

test.describe('automated accessibility audit', () => {
  test('public and authenticated portal landmarks have no detectable WCAG A/AA violations', async ({
    customer,
  }) => {
    for (const route of ['/', '/schedule', '/packages', '/shop', '/account']) {
      await customer.page.goto(route);
      await customer.page.getByRole('main').waitFor();
      await expectAccessible(customer.page, `portal ${route}`);
    }

    await customer.page.setViewportSize({ width: 390, height: 844 });
    await customer.page.goto('/');
    const opener = customer.page.getByRole('button', { name: 'Menu' });
    await opener.click();
    await expect(customer.page.getByRole('dialog', { name: 'Menu' })).toBeVisible();
    await expectAccessible(customer.page, 'portal mobile navigation');
    await customer.page.keyboard.press('Escape');
    await expect(opener).toBeFocused();
  });

  test('owner dashboard and representative data pages have no detectable WCAG A/AA violations', async ({
    browser,
    baseURL,
  }) => {
    const context = await browser.newContext({ baseURL });
    const page = await context.newPage();
    await loginAdmin(page, SEEDED.owner.email, SEEDED.owner.password);

    for (const route of ['/admin', '/admin/schedule', '/admin/customers', '/admin/settings/branding']) {
      await page.goto(route);
      await page.getByRole('main').waitFor();
      await expectAccessible(page, `admin ${route}`);
    }

    await context.close();
  });
});
