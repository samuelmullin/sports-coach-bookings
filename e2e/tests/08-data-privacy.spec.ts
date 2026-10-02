import { addReadyPlayer, bookSession, buyPackage, expect, openSession, ownerApi, test } from './fixtures';
import { SEEDED } from './helpers';

test.describe('PIPEDA: export and erasure', () => {
  test('a household can download its data and then erase it', async ({
    customer,
    playwright,
    baseURL,
  }) => {
    const { page, request } = customer;
    const first = `Erin${Date.now().toString().slice(-6)}`;
    const player = await addReadyPlayer(customer, { firstName: first, lastName: 'Privacy' });
    await request.put(`/api/portal/players/${player.id}/medical`, {
      data: { allergies: 'Peanuts', conditions: 'Asthma' },
    });
    await buyPackage(customer, 'Group U8-U10 3-Session Pack');
    const session = await openSession(customer, 'Group U8-U10');
    await bookSession(customer, player.id, session.id);

    await page.goto('/account');
    await page.getByRole('tab', { name: 'Your data' }).click();

    await test.step('download everything held about the household', async () => {
      const [download] = await Promise.all([
        page.waitForEvent('download'),
        page.getByRole('link', { name: 'Download my data' }).click(),
      ]);
      expect(download.suggestedFilename()).toBe('household-data.json');

      const path = await download.path();
      const data = JSON.parse(await (await import('node:fs/promises')).readFile(path, 'utf8'));
      expect(data.household.members[0].customer_user.email).toBe(customer.email);
      const exported = data.players.find((p: { player: { first_name: string } }) => p.player.first_name === first);
      expect(exported.medical_info).toMatchObject({ allergies: 'Peanuts', conditions: 'Asthma' });
      expect(exported.waiver_signatures.length).toBeGreaterThan(0);
      expect(data.bookings).toHaveLength(1);
      expect(data.credit_lots.length).toBeGreaterThan(0);
      expect(data.orders.length).toBeGreaterThan(0);
    });

    const openDialog = async () => {
      await page.getByRole('button', { name: 'Delete my account' }).click();
      return page.getByRole('dialog', { name: 'Delete your account?' });
    };

    await test.step('a wrong password is rejected next to the field', async () => {
      const dialog = await openDialog();
      await dialog.getByLabel(/Your password/).fill('definitely not it');
      await dialog.getByLabel(/Type ERASE/).fill('ERASE');
      await dialog.getByRole('button', { name: 'Permanently delete' }).click();
      await expect(dialog.getByText('That password is incorrect.')).toBeVisible();
      await dialog.getByRole('button', { name: 'Keep my account' }).click();
    });

    await test.step('an upcoming booking blocks the erasure and nothing is deleted', async () => {
      const dialog = await openDialog();
      await dialog.getByLabel(/Your password/).fill(customer.password);
      await dialog.getByLabel(/Type ERASE/).fill('ERASE');
      await dialog.getByRole('button', { name: 'Permanently delete' }).click();
      await expect(dialog.getByRole('alert')).toContainText('You have upcoming bookings. Cancel them first.');
      await dialog.getByRole('button', { name: 'Keep my account' }).click();

      const players = await (await request.get('/api/portal/players')).json();
      expect(players.data).toHaveLength(1);
    });

    await test.step('after cancelling the booking the household is erased and signed out', async () => {
      const upcoming = await (await request.get('/api/portal/bookings?scope=upcoming')).json();
      for (const row of upcoming.data) {
        await request.post(`/api/portal/bookings/${row.booking.id}/cancel`, { data: {} });
      }

      const dialog = await openDialog();
      await dialog.getByLabel(/Your password/).fill(customer.password);
      await dialog.getByLabel(/Type ERASE/).fill('ERASE');
      await dialog.getByRole('button', { name: 'Permanently delete' }).click();
      await page.waitForURL(/\/login/);
    });

    await test.step('the account is gone: the old credentials no longer work', async () => {
      const login = await request.post('/api/portal/session', {
        data: { email: customer.email, password: customer.password },
      });
      expect(login.status()).toBe(401);
      expect((await request.get('/api/portal/account/export')).status()).not.toBe(200);
    });

    await test.step('the club keeps the waiver record but not the signer\'s details', async () => {
      const owner = await ownerApi(playwright, baseURL, SEEDED.owner);
      const signatures = await (
        await owner.get(`/api/staff/waivers/signatures?player_id=${player.id}`)
      ).json();
      expect(signatures.data.length).toBeGreaterThan(0);
      for (const signature of signatures.data) {
        expect(signature.signer_name_typed).toBe('[erased]');
        expect(signature.user_agent).toBe('[erased]');
        expect(signature.pdf_key).toBeNull();
      }
      await owner.dispose();
    });
  });

  test('the Your data tab is reachable from the account page', async ({ customer }) => {
    await customer.page.goto('/account');
    await customer.page.getByRole('tab', { name: 'Your data' }).click();
    await expect(customer.page.getByRole('heading', { name: 'Download your data' })).toBeVisible();
    await expect(customer.page.getByRole('heading', { name: 'Delete your account' })).toBeVisible();
  });
});
