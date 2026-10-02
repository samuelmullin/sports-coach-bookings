import { addReadyPlayer, buyPackage, expect, signAllWaivers, test } from './fixtures';
import { dobForAge, pickOption } from './helpers';

test.describe('booking a session', () => {
  test('books a group session with purchased sessions and the balance drops', async ({
    customer,
  }) => {
    const { page, request } = customer;
    const player = await addReadyPlayer(customer, { firstName: 'Avery', lastName: 'Booker' });
    await buyPackage(customer, 'Group U8-U10 3-Session Pack');

    await test.step('pick a session from the schedule', async () => {
      await page.goto('/schedule');
      const session = page.getByRole('listitem').filter({ hasText: 'Group U8-U10' }).first();
      await expect(session).toBeVisible();
      await session.getByRole('link', { name: 'Book' }).click();
      await expect(page.getByRole('heading', { name: 'Book Group U8-U10' })).toBeVisible();
    });

    await test.step('choose the player and pay with sessions', async () => {
      await pickOption(page, 'Player', `${player.firstName} ${player.lastName}`);
      const sessions = page.getByRole('radio', { name: /Use sessions/ });
      await expect(sessions).toBeEnabled();
      await expect(sessions).toBeChecked();
      await page.getByRole('button', { name: 'Confirm booking' }).click();
    });

    await test.step('the booking is confirmed and listed', async () => {
      await expect(page.getByRole('heading', { name: "You're booked!" })).toBeVisible();
      await page.goto('/bookings');
      const row = page.getByRole('listitem').filter({ hasText: 'Avery Booker' });
      await expect(row).toBeVisible();
      await expect(row).toContainText('confirmed');
      await expect(row).toContainText('Group U8-U10');
    });

    await test.step('one session was spent', async () => {
      const credits = await (await request.get('/api/portal/credits')).json();
      expect(JSON.stringify(credits.data)).toMatch(/"amount":2/);
    });
  });

  test('a player with unsigned waivers cannot be booked until they are signed', async ({
    customer,
  }) => {
    const { page, request } = customer;
    await buyPackage(customer, 'Group U8-U10 3-Session Pack');

    // A player with an emergency contact but no signed waivers.
    const created = await (
      await request.post('/api/portal/players', {
        data: { first_name: 'Quinn', last_name: 'Unsigned', date_of_birth: dobForAge(9) },
      })
    ).json();
    await request.post(`/api/portal/players/${created.id}/emergency_contacts`, {
      data: { name: 'Pat', phone: '+19025550199', relationship: 'Parent', priority: 1 },
    });

    await page.goto('/schedule');
    await page
      .getByRole('listitem')
      .filter({ hasText: 'Group U8-U10' })
      .first()
      .getByRole('link', { name: 'Book' })
      .click();
    const sessionUrl = page.url();
    await pickOption(page, 'Player', 'Quinn Unsigned');

    await test.step('the page blocks the booking and points at the waivers', async () => {
      const waiverCheck = page.getByText('Required waivers signed');
      await expect(waiverCheck).toBeVisible();
      await expect(page.getByRole('button', { name: 'Confirm booking' })).toBeDisabled();
      await expect(page.getByRole('link', { name: 'Fix' }).last()).toHaveAttribute(
        'href',
        new RegExp(`/players/${created.id}\\?tab=waivers`),
      );
    });

    await test.step('the server refuses the booking too, and no session is spent', async () => {
      const sessionId = sessionUrl.split('/book/')[1];
      const refused = await request.post('/api/portal/bookings', {
        data: { player_id: created.id, session_id: sessionId, method: 'credits' },
      });
      expect(refused.ok()).toBe(false);

      const bookings = await (await request.get('/api/portal/bookings')).json();
      expect(bookings.data).toHaveLength(0);
      const credits = await (await request.get('/api/portal/credits')).json();
      expect(JSON.stringify(credits.data)).toMatch(/"amount":3/);
    });

    await test.step('after signing the waivers the booking goes through', async () => {
      await signAllWaivers(customer, created.id);
      await page.reload();
      await pickOption(page, 'Player', 'Quinn Unsigned');
      await expect(page.getByRole('button', { name: 'Confirm booking' })).toBeEnabled();
      await page.getByRole('button', { name: 'Confirm booking' }).click();
      await expect(page.getByRole('heading', { name: "You're booked!" })).toBeVisible();
    });
  });
});
