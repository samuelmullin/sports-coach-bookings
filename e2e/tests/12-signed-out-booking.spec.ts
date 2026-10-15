import { expect, test } from '@playwright/test';
import { PASSWORD, dobForAge, linkFrom, uniqueEmail, waitForEmail } from './helpers';

test.use({ viewport: { width: 1280, height: 900 } });

test.describe('signed-out booking', () => {
  test('a new visitor registers, adds a player, signs waivers and reaches payment without leaving the booking page', async ({
    page,
    context,
    request,
  }) => {
    const email = uniqueEmail('inline');

    await test.step('Book from the schedule while signed out', async () => {
      await page.goto('/schedule');
      await page
        .getByRole('listitem')
        .filter({ hasText: 'Group U8-U10' })
        .first()
        .getByRole('link', { name: 'Book' })
        .click();
      await expect(page.getByRole('heading', { name: 'Book Group U8-U10' })).toBeVisible();
      await expect(
        page.getByRole('heading', { name: 'Create your account to book' }),
      ).toBeVisible();
    });

    const bookingUrl = page.url();

    await test.step('create the account on the booking page', async () => {
      await page.getByLabel('First name').fill('Jules');
      await page.getByLabel('Last name').fill('Inline');
      await page.getByLabel('Email').fill(email);
      await page.getByRole('textbox', { name: 'Phone' }).fill('9025550143');
      await page.getByLabel('Password', { exact: true }).fill(PASSWORD);
      await page.getByLabel(/I agree to the/).check();
      await page.getByRole('button', { name: 'Create account' }).click();
      await expect(page).toHaveURL(bookingUrl);
    });

    await test.step('the add-player form opens by itself', async () => {
      const dialog = page.getByRole('dialog');
      await dialog.getByLabel('First name').fill('Robin');
      await dialog.getByLabel('Last name').fill('Inline');
      await dialog.getByLabel('Date of birth').fill(dobForAge(9));
      await dialog.getByRole('button', { name: 'Continue' }).click();
      await dialog.getByLabel('Name').fill('Grandma Inline');
      await dialog.getByLabel('Phone').fill('9025550178');
      await dialog.getByLabel('Relationship').fill('Grandmother');
      await dialog.getByRole('button', { name: 'Save player' }).click();
      await expect(dialog).toBeHidden();
      await expect(page).toHaveURL(bookingUrl);
    });

    await test.step('sign each required waiver in place', async () => {
      const sign = page.getByRole('button', { name: 'Read & sign' });
      await expect(sign).toBeVisible();
      // The seeded club requires two waivers; the check row offers one at a time.
      for (let remaining = 2; remaining > 0; remaining--) {
        await expect(sign).toBeVisible();
        await sign.click();
        const drawer = page.getByRole('dialog');
        await drawer.getByLabel('Type your full name').fill('Jules Inline');
        await drawer.getByLabel('Relationship to player').fill('Parent');
        await drawer.getByRole('checkbox').check();
        await drawer.getByRole('button', { name: 'Sign waiver' }).click();
        await expect(drawer).toBeHidden();
      }
      await expect(page.getByRole('button', { name: 'Read & sign' })).toHaveCount(0);
      await expect(page).toHaveURL(bookingUrl);
    });

    await test.step('payment is blocked until the email is confirmed', async () => {
      await expect(page.getByText(/Confirm your email to finish booking/)).toBeVisible();
      await expect(page.getByRole('button', { name: 'Continue to payment' })).toBeDisabled();
    });

    await test.step('confirming in another tab unblocks this one', async () => {
      const message = await waitForEmail(request, email, /confirm/i);
      const link = new URL(
        linkFrom(message, /https?:\/\/[^\s"'<>]*confirm-email\?token=[^\s"'<>]+/),
      );
      const other = await context.newPage();
      await other.goto(link.pathname + link.search);
      await expect(other.getByRole('status')).toContainText('Your email is confirmed');
      await other.close();
      await expect(page.getByRole('button', { name: 'Continue to payment' })).toBeEnabled({
        timeout: 15_000,
      });
    });

    await test.step('continue to payment holds the seat in the cart', async () => {
      await page.getByRole('button', { name: 'Continue to payment' }).click();
      await expect(page).toHaveURL(/\/cart$/);
      await expect(page.getByRole('heading', { name: 'Cart' })).toBeVisible();
    });
  });
});
