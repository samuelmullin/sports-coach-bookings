import { addReadyPlayer, bookOnBehalf, createStartedSession, expect, ownerApi, test } from './fixtures';
import { SEEDED, loginAdmin } from './helpers';

test.describe('coach workflow', () => {
  test('a coach reviews the roster, takes attendance, shares feedback, and the family sees it', async ({
    customer,
    browser,
    baseURL,
    playwright,
  }) => {
    // Unique per run: rosters accumulate players across runs of the shared database.
    const first = `Alex${Date.now().toString().slice(-6)}`;
    const player = await addReadyPlayer(customer, {
      firstName: first,
      lastName: 'Coachee',
      contactName: `Pat ${first}`,
    });
    await customer.request.put(`/api/portal/players/${player.id}/medical`, {
      data: { allergies: 'Peanuts' },
    });

    // Attendance and feedback open when a session starts, so create one that has
    // just started and book the player into it on the family's behalf.
    const owner = await ownerApi(playwright, baseURL, SEEDED.owner);
    const session = await createStartedSession(owner, 'Group U8-U10', SEEDED.coach.email);
    await bookOnBehalf(owner, player.id, session.id);

    const coachContext = await browser.newContext({ baseURL });
    const coach = await coachContext.newPage();
    await loginAdmin(coach, SEEDED.coach.email, SEEDED.coach.password);

    await test.step('the session is on the coach\'s schedule with the roster', async () => {
      await expect(coach.getByRole('heading', { name: 'My sessions' })).toBeVisible();
      await expect(coach.locator(`a[href="/admin/my-sessions/${session.id}"]`).first()).toBeVisible();
      await coach.goto(`/admin/my-sessions/${session.id}`);
      await expect(coach.getByRole('heading', { level: 1 })).toBeVisible();
      const row = coach.getByTestId('roster-row').filter({ hasText: first });
      await expect(row).toHaveCount(1);
      await expect(row.getByRole('link', { name: first })).toBeVisible();
      await expect(row.getByText(`Emergency contact: Pat ${first}`)).toBeVisible();
      await expect(row.getByText('Medical info on file')).toBeVisible();
    });

    await test.step('mark the player as attended', async () => {
      await coach.getByRole('button', { name: `Mark ${first} attended` }).click();
      await expect(coach.getByRole('button', { name: `Mark ${first} attended` })).toHaveAttribute(
        'aria-pressed',
        'true',
      );
    });

    await test.step('write and share feedback with the family', async () => {
      await coach.getByRole('button', { name: `Feedback for ${first}` }).click();
      const dialog = coach.getByRole('dialog', { name: `Feedback for ${first}` });
      await dialog.getByLabel('Session note').fill('Great first touch today, keep scanning early.');
      await dialog.getByLabel('Focus next session').fill('Weak-foot passing');
      await dialog.getByRole('button', { name: 'First touch 4' }).click();
      await dialog.getByRole('button', { name: 'Share with family' }).click();

      // Sharing cannot be undone, so the app asks first.
      const confirm = coach.getByRole('dialog', { name: 'Share feedback with the family?' });
      await expect(confirm).toContainText('cannot be unshared');
      await confirm.getByRole('button', { name: 'Share now' }).click();
      await expect(confirm).toBeHidden();
      await expect(coach.getByTestId('roster-row').filter({ hasText: first }).getByText('Shared')).toBeVisible();
    });

    await test.step('the family reads the shared feedback in the portal', async () => {
      await customer.page.goto(`/players/${player.id}`);
      await customer.page.getByRole('tab', { name: 'Feedback' }).click();
      await expect(customer.page.getByText('Great first touch today, keep scanning early.')).toBeVisible();
      await expect(customer.page.getByText('Weak-foot passing')).toBeVisible();
    });

    await coachContext.close();
    await owner.dispose();
  });

  test('a coach cannot see sessions or players outside their assignments', async ({
    browser,
    baseURL,
  }) => {
    const context = await browser.newContext({ baseURL });
    const coach = await context.newPage();
    await loginAdmin(coach, SEEDED.coach.email, SEEDED.coach.password);

    // Coaches only get the coach navigation, not catalog/orders/customers admin.
    const nav = coach.getByRole('navigation');
    await expect(nav.getByRole('link', { name: 'My sessions' })).toBeVisible();
    await expect(nav.getByRole('link', { name: 'Orders' })).toHaveCount(0);
    await expect(nav.getByRole('link', { name: 'Customers' })).toHaveCount(0);

    // Admin-only pages refuse a coach even by direct URL.
    await coach.goto('/admin/orders');
    await expect(coach.getByRole('heading', { name: 'Orders' })).toHaveCount(0);
    await context.close();
  });
});
