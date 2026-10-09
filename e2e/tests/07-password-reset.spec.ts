import { expect, test } from './fixtures';
import { linkFrom, loginPortal, uniqueEmail, waitForEmail } from './helpers';
import { expect as baseExpect, test as baseTest } from '@playwright/test';

const NEW_PASSWORD = 'a brand new e2e password 456';
const PLATFORM = `http://localhost:${process.env.E2E_PORT ?? '4010'}`;

test.describe('customer password reset', () => {
  test('resets the password from the emailed link and signs in with it', async ({
    customer,
    browser,
    baseURL,
  }) => {
    const context = await browser.newContext({ baseURL });
    const page = await context.newPage();

    await page.goto('/forgot-password');
    await page.getByLabel('Email').fill(customer.email);
    await page.getByRole('button', { name: 'Send reset link' }).click();
    await expect(page.getByRole('status')).toContainText('a reset link is on its way');

    const message = await waitForEmail(context.request, customer.email, /password/i);
    const link = new URL(linkFrom(message, /https?:\/\/[^\s"'<>]*reset-password\?token=[^\s"'<>]+/));
    // The link opens on the customer's own club host.
    expect(link.host).toBe(new URL(baseURL as string).host);

    await page.goto(link.pathname + link.search);
    await page.locator('input[name="password"]').fill(NEW_PASSWORD);
    await page.locator('input[name="confirm"]').fill(NEW_PASSWORD);
    await page.getByRole('button', { name: 'Reset password' }).click();
    await expect(page.getByText('Your password has been updated')).toBeVisible();

    await loginPortal(page, customer.email, NEW_PASSWORD);

    // The old password no longer works.
    const stale = await context.request.post('/api/portal/session', {
      data: { email: customer.email, password: customer.password },
    });
    expect(stale.status()).toBe(401);
    await context.close();
  });
});

baseTest.describe('staff password reset', () => {
  baseTest('a club owner resets their password from the emailed link', async ({
    page,
    request,
  }) => {
    const slug = `reset${Date.now().toString().slice(-8)}`;
    const email = uniqueEmail('resetowner');
    const original = 'an original e2e password 123';

    // A dedicated owner, so the seeded accounts other journeys use stay untouched.
    const signup = await request.post(`${PLATFORM}/api/platform/signup`, {
      data: {
        name: 'Reset Club',
        slug,
        timezone: 'America/Toronto',
        currency: 'CAD',
        email,
        password: original,
      },
    });
    baseExpect(signup.status()).toBe(201);

    await page.goto(`${PLATFORM}/admin/forgot-password`);
    await page.getByLabel('Email').fill(email);
    await page.getByRole('button', { name: 'Send reset link' }).click();
    await baseExpect(page.getByRole('status')).toContainText('a reset link is on its way');

    // Staff accounts are platform-wide, so this email used to be dropped (no tenant).
    const message = await waitForEmail(request, email, /password/i);
    const link = new URL(linkFrom(message, /https?:\/\/[^\s"'<>]*reset-password\?token=[^\s"'<>]+/));
    baseExpect(link.pathname).toBe('/admin/reset-password');

    await page.goto(link.pathname + link.search);
    await page.locator('input[name="password"]').fill(NEW_PASSWORD);
    await page.locator('input[name="confirm"]').fill(NEW_PASSWORD);
    await page.getByRole('button', { name: 'Reset password' }).click();
    await baseExpect(page.getByText('Your password has been updated')).toBeVisible();

    const login = await request.post(`${PLATFORM}/api/platform/session`, {
      data: { email, password: NEW_PASSWORD },
    });
    baseExpect(login.status()).toBe(201);
    const stale = await request.post(`${PLATFORM}/api/platform/session`, {
      data: { email, password: original },
    });
    baseExpect(stale.status()).toBe(401);
  });
});
