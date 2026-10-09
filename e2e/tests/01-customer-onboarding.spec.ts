import { expect, test } from '@playwright/test';
import { PASSWORD, linkFrom, uniqueEmail, waitForEmail } from './helpers';

// A laptop-height viewport on purpose: the add-player drawer once overflowed it
// with no way to scroll to "Continue".
test.use({ viewport: { width: 1280, height: 720 } });

test.describe('customer onboarding', () => {
  test('registers, confirms email, adds a player, signs waivers, and downloads the PDF', async ({
    page,
    request,
  }) => {
    const email = uniqueEmail('onboard');

    await test.step('register a household', async () => {
      await page.goto('/register');
      await page.getByLabel('First name').fill('Riley');
      await page.getByLabel('Last name').fill('Onboard');
      await page.getByLabel('Email').fill(email);
      await page.getByRole('textbox', { name: 'Phone' }).fill('9025550142');
      await page.getByLabel('Password', { exact: true }).fill(PASSWORD);
      await page.getByLabel('Confirm password').fill(PASSWORD);
      await page.getByLabel('I accept the terms of service').check();
      await page.getByLabel('I accept the privacy policy').check();
      await page.getByRole('button', { name: 'Create account' }).click();
      await expect(page.getByRole('button', { name: 'Sign out' })).toBeVisible();
    });

    await test.step('confirm the email address from the link in the email', async () => {
      const message = await waitForEmail(request, email, /confirm/i);
      const link = new URL(linkFrom(message, /https?:\/\/[^\s"'<>]*confirm-email\?token=[^\s"'<>]+/));
      // The link must open on the tenant's own host, not the platform host.
      expect(link.host).toBe(new URL(page.url()).host);
      await page.goto(link.pathname + link.search);
      await expect(page.getByRole('status')).toContainText('Your email is confirmed');
      await expect(page.getByRole('alert')).toHaveCount(0);
    });

    await test.step('add a player with just the two required steps', async () => {
      await page.goto('/players');
      await page.getByRole('button', { name: 'Add player' }).first().click();
      const dialog = page.getByRole('dialog');

      await dialog.getByLabel('First name').fill('Sky');
      await dialog.getByLabel('Last name').fill('Onboard');
      await dialog.getByLabel('Date of birth').fill('2015-06-01');
      await dialog.getByRole('button', { name: 'Continue' }).click();

      await expect(dialog.getByText('Step 2 of 2')).toBeVisible();
      await dialog.getByLabel('Name').fill('Grandma Onboard');
      await dialog.getByLabel('Phone').fill('9025550177');
      await dialog.getByLabel('Relationship').fill('Grandmother');
      await dialog.getByRole('button', { name: 'Save player' }).click();

      await expect(dialog).toBeHidden();
      const card = page.getByRole('listitem').filter({ hasText: 'Sky Onboard' });
      await expect(card).toBeVisible();
      await expect(card.getByText('Action needed')).toBeVisible();
    });

    await test.step('sign every required waiver', async () => {
      await page
        .getByRole('listitem')
        .filter({ hasText: 'Sky Onboard' })
        .getByRole('link', { name: 'Manage player' })
        .click();
      await page.getByRole('tab', { name: 'Waivers' }).click();

      const signLinks = page.getByRole('link', { name: 'Read & sign' });
      await expect(signLinks).toHaveCount(2);

      let pdfHref = '';
      for (let remaining = 2; remaining > 0; remaining--) {
        await expect(signLinks).toHaveCount(remaining);
        await signLinks.first().click();
        await page.getByLabel('Type your full name').fill('Riley Onboard');
        await page.getByLabel('Relationship to player').fill('Parent');
        await page.getByRole('checkbox').check();
        await page.getByRole('button', { name: 'Sign waiver' }).click();
        await expect(page.getByRole('heading', { name: 'Waiver signed' })).toBeVisible();
        pdfHref = (await page.getByRole('link', { name: /download signed pdf/i }).getAttribute('href')) ?? '';
        await page.getByRole('button', { name: 'Back to player' }).click();
        await page.getByRole('tab', { name: 'Waivers' }).click();
      }
      await expect(page.getByRole('link', { name: 'Read & sign' })).toHaveCount(0);

      await test.step('the signed PDF downloads as a real PDF', async () => {
        const response = await page.request.get(pdfHref);
        expect(response.status()).toBe(200);
        expect(response.headers()['content-type']).toBe('application/pdf');
        expect(response.headers()['content-disposition']).toContain('attachment');
        const bytes = await response.body();
        expect(bytes.subarray(0, 5).toString()).toBe('%PDF-');
        expect(bytes.length).toBeGreaterThan(1000);
      });
    });

    await test.step('the player no longer needs any action', async () => {
      await page.goto('/players');
      const card = page.getByRole('listitem').filter({ hasText: 'Sky Onboard' });
      await expect(card.getByText('Action needed')).toHaveCount(0);
    });
  });
});
