import { expect, test } from '@playwright/test';
import { PASSWORD, linkFrom, uniqueEmail, waitForEmail } from './helpers';

const PLATFORM = `http://localhost:${process.env.E2E_PORT ?? '4010'}`;

async function openSignup(page: import('@playwright/test').Page) {
  await page.goto(`${PLATFORM}/admin/signup`);
  await expect(page.getByRole('heading', { name: 'Create your coaching business' })).toBeVisible();
}

test.describe('club (tenant) signup', () => {
  test('a web address that is already taken is rejected', async ({ page }) => {
    await openSignup(page);
    await page.getByLabel('Business name').fill('Clone Of Demo');
    await page.getByLabel('Web address').fill('demo');
    await page.getByRole('button', { name: 'Next' }).click();
    await page.getByRole('button', { name: 'Next' }).click();
    await page.getByLabel('Email').fill(uniqueEmail('dupe'));
    await page.getByLabel('Password').fill(PASSWORD);
    await page.getByRole('button', { name: 'Create account' }).click();

    // The server rejects it; the form returns to the address step and says why.
    await expect(page.getByLabel('Web address')).toBeVisible();
    await expect(page.getByText('That address is already taken')).toBeVisible();
  });

  test('creates a club, confirms the owner, and the club gets its own host', async ({
    page,
    request,
  }) => {
    const slug = `club${Date.now().toString().slice(-8)}`;
    const email = uniqueEmail('owner');

    await test.step('walk through the three signup steps', async () => {
      await openSignup(page);
      await page.getByLabel('Business name').fill('E2E Soccer Club');
      await page.getByLabel('Web address').fill(slug);
      await page.getByRole('button', { name: 'Next' }).click();

      await expect(page.getByLabel('Timezone')).toBeVisible();
      await page.getByRole('button', { name: 'Next' }).click();

      await page.getByLabel('Email').fill(email);
      await page.getByLabel('Password').fill(PASSWORD);
      await page.getByRole('button', { name: 'Create account' }).click();
    });

    await test.step('the owner confirms their email from the link', async () => {
      const message = await waitForEmail(request, email, /confirm/i);
      const link = new URL(linkFrom(message, /https?:\/\/[^\s"'<>]*confirm-email\?token=[^\s"'<>]+/));
      expect(link.pathname).toBe('/admin/confirm-email');
      await page.goto(link.pathname + link.search);
      await expect(page.getByRole('status')).toContainText('Your email is confirmed');
      await expect(page.getByRole('alert')).toHaveCount(0);
    });

    await test.step('the new club is served on its own host with its own branding', async () => {
      // Via the browser: Chromium resolves any *.localhost name to loopback.
      const clubHost = `http://${slug}.localhost:${process.env.E2E_PORT ?? '4010'}`;
      await page.goto(`${clubHost}/api/portal/ping`);
      expect(JSON.parse(await page.locator('body').innerText())).toMatchObject({ tenant: slug });

      await page.goto(`${clubHost}/`);
      await expect(page.getByText('E2E Soccer Club').first()).toBeVisible();
    });
  });
});
