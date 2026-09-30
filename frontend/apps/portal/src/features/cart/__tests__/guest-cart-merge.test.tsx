import { HttpResponse, http } from 'msw';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { setMockCustomerSession } from '@scb/mocks';
import { server } from '@scb/mocks/server';
import { getPortalExtraHandlers } from '../../../api/extra-handlers';
import { renderWithProviders } from '../../../test/render';
import { CartPage } from '../CartPage';
import { GuestCartMerge } from '../GuestCartMerge';
import { addGuestLine, clearGuestCart, readGuestCart } from '../guest-cart';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
beforeEach(() => {
  server.use(...getPortalExtraHandlers());
  setMockCustomerSession({ signedIn: true });
  clearGuestCart();
});
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const emptyCart = {
  id: 'cart-1',
  household_id: 'h1',
  discount_code: null,
  expires_at: null,
  lines: [],
  pricing: { lines: [], subtotal: 0, discount_total: 0, tax_total: 0, total: 0 },
};

const player = {
  id: 'player-1',
  household_id: 'h1',
  first_name: 'Sam',
  last_name: 'Player',
};

function seedGuestCart() {
  addGuestLine({
    id: 'package:pkg-1',
    type: 'package',
    ref_id: 'pkg-1',
    quantity: 1,
    snapshot: { title: 'Summer package', priceMinor: 20000, currency: 'CAD' },
  });
  addGuestLine({
    id: 'product:var-1',
    type: 'product',
    ref_id: 'var-1',
    quantity: 2,
    snapshot: { title: 'Home jersey', priceMinor: 5000, currency: 'CAD' },
  });
  addGuestLine({
    id: 'drop_in:session-1',
    type: 'drop_in',
    ref_id: 'session-1',
    quantity: 1,
    snapshot: {
      title: 'U10 Skills',
      priceMinor: 2000,
      currency: 'CAD',
      sessionId: 'session-1',
      startsAt: '2026-10-01T14:00:00Z',
      venueName: 'Field A',
    },
  });
}

function Harness() {
  return (
    <>
      <GuestCartMerge />
      <CartPage onRedirect={() => undefined} />
    </>
  );
}

function commonHandlers() {
  server.use(
    http.get('/api/portal/cart', () => HttpResponse.json(emptyCart)),
    http.get('/api/portal/players', () => HttpResponse.json({ data: [player] })),
  );
}

describe('guest cart merge', () => {
  it('moves package and product lines to the server and leaves drop-ins pending', async () => {
    commonHandlers();
    const posts: Array<Record<string, unknown>> = [];
    server.use(
      http.post('/api/portal/cart/lines', async ({ request }) => {
        posts.push((await request.json()) as Record<string, unknown>);
        return HttpResponse.json({ ...emptyCart, lines: [] }, { status: 201 });
      }),
    );
    seedGuestCart();

    renderWithProviders(<Harness />, { withAuth: true });

    await waitFor(() => expect(posts).toHaveLength(2));
    expect(posts).toEqual(
      expect.arrayContaining([
        { type: 'package', ref_id: 'pkg-1', quantity: 1 },
        { type: 'product', ref_id: 'var-1', quantity: 2 },
      ]),
    );

    await waitFor(() => {
      const remaining = readGuestCart();
      expect(remaining).toHaveLength(1);
      expect(remaining[0]?.type).toBe('drop_in');
    });

    expect(await screen.findByText('Drop-ins to confirm')).toBeInTheDocument();
    expect(screen.getByText('U10 Skills')).toBeInTheDocument();
    expect(screen.getByRole('combobox', { name: 'Player' })).toBeInTheDocument();
  });

  it('resolves a pending drop-in with a player and adds it to the server cart', async () => {
    commonHandlers();
    let bookingBody: Record<string, unknown> | undefined;
    const linePosts: Array<Record<string, unknown>> = [];
    server.use(
      http.post('/api/portal/cart/lines', async ({ request }) => {
        linePosts.push((await request.json()) as Record<string, unknown>);
        return HttpResponse.json({ ...emptyCart, lines: [] }, { status: 201 });
      }),
      http.post('/api/portal/bookings', async ({ request }) => {
        bookingBody = (await request.json()) as Record<string, unknown>;
        return HttpResponse.json(
          {
            id: 'hold-1',
            session_id: 'session-1',
            player_id: 'player-1',
            status: 'held',
            payment_method: 'paid',
          },
          { status: 201 },
        );
      }),
    );
    seedGuestCart();

    renderWithProviders(<Harness />, { withAuth: true });

    await screen.findByText('Drop-ins to confirm');
    await userEvent.click(screen.getByRole('button', { name: 'Add to cart' }));

    await waitFor(() =>
      expect(bookingBody).toMatchObject({
        player_id: 'player-1',
        session_id: 'session-1',
        method: 'paid',
      }),
    );
    await waitFor(() =>
      expect(linePosts).toContainEqual({ type: 'drop_in', ref_id: 'hold-1', quantity: 1 }),
    );
    await waitFor(() => expect(readGuestCart()).toHaveLength(0));
  });

  it('keeps a line in the guest cart when its merge request fails', async () => {
    commonHandlers();
    server.use(
      http.post('/api/portal/cart/lines', async ({ request }) => {
        const body = (await request.json()) as Record<string, unknown>;
        if (body.type === 'product') {
          return HttpResponse.json(
            { error: { code: 'out_of_stock', message: 'That item is sold out' } },
            { status: 422 },
          );
        }
        return HttpResponse.json({ ...emptyCart, lines: [] }, { status: 201 });
      }),
    );
    seedGuestCart();

    renderWithProviders(<Harness />, { withAuth: true });

    await waitFor(() => {
      const remaining = readGuestCart();
      expect(remaining.some((line) => line.type === 'product')).toBe(true);
      expect(remaining.some((line) => line.type === 'package')).toBe(false);
      expect(remaining.some((line) => line.type === 'drop_in')).toBe(true);
    });
  });
});
