import { addReadyPlayer, buyPackage, expect, test, type Customer, type Player } from './fixtures';
import { pickOption } from './helpers';

async function bookFirstGroupSession(customer: Customer, player: Player) {
  const { page } = customer;
  await page.goto('/schedule');
  await page
    .getByRole('listitem')
    .filter({ hasText: 'Group U8-U10' })
    .first()
    .getByRole('link', { name: 'Book' })
    .click();
  await pickOption(page, 'Player', `${player.firstName} ${player.lastName}`);
  await page.getByRole('button', { name: 'Confirm booking' }).click();
  await expect(page.getByRole('heading', { name: "You're booked!" })).toBeVisible();
}

async function sessionsLeft(customer: Customer): Promise<number> {
  const credits = await (await customer.request.get('/api/portal/credits')).json();
  return (credits.data as Array<{ amount: number }>).reduce((sum, entry) => sum + entry.amount, 0);
}

test.describe('cancelling and rebooking', () => {
  test('cancelling well ahead of the session returns the session credit', async ({ customer }) => {
    const { page } = customer;
    const player = await addReadyPlayer(customer, { firstName: 'Casey', lastName: 'Cancel' });
    await buyPackage(customer, 'Group U8-U10 3-Session Pack');
    await bookFirstGroupSession(customer, player);
    expect(await sessionsLeft(customer)).toBe(2);

    await page.goto('/bookings');
    const card = page.getByTestId('booking-card').filter({ hasText: 'Casey Cancel' });
    await expect(card).toContainText('confirmed');
    await card.getByRole('button', { name: 'Cancel' }).click();

    const dialog = page.getByRole('dialog', { name: 'Cancel this booking?' });
    await expect(dialog).toContainText('Your sessions will be returned');
    await dialog.getByRole('button', { name: 'Cancel booking' }).click();
    await expect(dialog).toBeHidden();

    // The booking leaves "Upcoming" and the session is back in the balance.
    await expect(page.getByTestId('booking-card').filter({ hasText: 'Casey Cancel' })).toHaveCount(0);
    await page.getByRole('button', { name: 'Past' }).click();
    const past = page.getByTestId('booking-card').filter({ hasText: 'Casey Cancel' });
    await expect(past).toContainText('cancelled');
    expect(await sessionsLeft(customer)).toBe(3);
  });

  test('keeping the booking leaves everything unchanged', async ({ customer }) => {
    const { page } = customer;
    const player = await addReadyPlayer(customer, { firstName: 'Kit', lastName: 'Keeper' });
    await buyPackage(customer, 'Group U8-U10 3-Session Pack');
    await bookFirstGroupSession(customer, player);

    await page.goto('/bookings');
    const card = page.getByTestId('booking-card').filter({ hasText: 'Kit Keeper' });
    await card.getByRole('button', { name: 'Cancel' }).click();
    await page.getByRole('dialog').getByRole('button', { name: 'Keep booking' }).click();

    await expect(card).toContainText('confirmed');
    expect(await sessionsLeft(customer)).toBe(2);
  });
});
