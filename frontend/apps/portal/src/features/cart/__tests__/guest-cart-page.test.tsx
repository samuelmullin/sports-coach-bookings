import { HttpResponse, http } from 'msw';
import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { server } from '@scb/mocks/server';
import { getPortalExtraHandlers } from '../../../api/extra-handlers';
import { renderWithProviders } from '../../../test/render';
import { CartPage } from '../CartPage';
import { addGuestLine, clearGuestCart, readGuestCart } from '../guest-cart';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
beforeEach(() => {
  server.use(...getPortalExtraHandlers());
  server.use(http.get('/api/portal/account', () => new HttpResponse(null, { status: 401 })));
  clearGuestCart();
});
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

function seed() {
  addGuestLine({
    id: 'package:pkg-1',
    type: 'package',
    ref_id: 'pkg-1',
    quantity: 1,
    snapshot: { title: 'Summer package', priceMinor: 10000, currency: 'CAD' },
  });
}

describe('CartPage (anonymous)', () => {
  it('renders guest lines, subtotal and the sign-in CTAs', async () => {
    seed();

    renderWithProviders(<CartPage onRedirect={() => undefined} />, { withAuth: true });

    expect(await screen.findByText('Summer package')).toBeInTheDocument();
    expect(screen.getByText('Subtotal')).toBeInTheDocument();

    const money = Array.from(document.querySelectorAll('[data-currency="CAD"]')).map(
      (element) => element.textContent ?? '',
    );
    expect(money.some((text) => text.includes('100'))).toBe(true);

    expect(screen.getByRole('link', { name: 'Sign in to check out' })).toHaveAttribute(
      'href',
      '/login',
    );
    expect(screen.getByRole('link', { name: 'Create an account' })).toHaveAttribute(
      'href',
      '/register',
    );
  });

  it('updates quantity and removes guest lines', async () => {
    seed();

    renderWithProviders(<CartPage onRedirect={() => undefined} />, { withAuth: true });

    const row = (await screen.findByText('Summer package')).closest('li');
    expect(row).not.toBeNull();

    await userEvent.click(
      within(row as HTMLElement).getByRole('button', { name: 'Increase quantity' }),
    );
    expect(readGuestCart()[0]?.quantity).toBe(2);

    await userEvent.click(
      within(row as HTMLElement).getByRole('button', { name: 'Remove Summer package' }),
    );
    expect(readGuestCart()).toHaveLength(0);
    expect(await screen.findByText('Your cart is empty')).toBeInTheDocument();
  });
});
