import { HttpResponse, http } from 'msw';
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { server } from '@scb/mocks/server';
import { getPortalExtraHandlers } from '../../../api/extra-handlers';
import { renderWithProviders } from '../../../test/render';
import { AddToCartButton } from '../AddToCartButton';
import { clearGuestCart, readGuestCart } from '../guest-cart';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
beforeEach(() => {
  server.use(...getPortalExtraHandlers());
  clearGuestCart();
});
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

describe('AddToCartButton (anonymous)', () => {
  it('adds a persisted guest line and toasts instead of redirecting', async () => {
    server.use(http.get('/api/portal/account', () => new HttpResponse(null, { status: 401 })));

    renderWithProviders(
      <AddToCartButton
        type="package"
        refId="pkg-1"
        title="Summer package"
        subtitle="10 sessions"
        priceMinor={20000}
        currency="CAD"
      />,
      { withAuth: true },
    );

    await userEvent.click(await screen.findByRole('button', { name: 'Add to cart' }));

    expect(await screen.findByText('Added to cart')).toBeInTheDocument();
    expect(screen.queryByText('Sign in to purchase')).not.toBeInTheDocument();

    const lines = readGuestCart();
    expect(lines).toHaveLength(1);
    expect(lines[0]).toMatchObject({
      id: 'package:pkg-1',
      type: 'package',
      ref_id: 'pkg-1',
      quantity: 1,
      snapshot: { title: 'Summer package', priceMinor: 20000, currency: 'CAD' },
    });
  });

  it('increments quantity when the same item is added again', async () => {
    server.use(http.get('/api/portal/account', () => new HttpResponse(null, { status: 401 })));

    renderWithProviders(
      <AddToCartButton type="product" refId="variant-9" title="Home jersey" priceMinor={5000} />,
      { withAuth: true },
    );

    const button = await screen.findByRole('button', { name: 'Add to cart' });
    await userEvent.click(button);
    await userEvent.click(button);

    const lines = readGuestCart();
    expect(lines).toHaveLength(1);
    expect(lines[0]?.quantity).toBe(2);
  });
});
