import { HttpResponse, http } from 'msw';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { setMockCustomerSession } from '@scb/mocks';
import { server } from '@scb/mocks/server';
import { getPortalExtraHandlers } from '../../../api/extra-handlers';
import { renderWithProviders } from '../../../test/render';
import { CartPage } from '../CartPage';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
beforeEach(() => {
  server.use(...getPortalExtraHandlers());
  setMockCustomerSession({ signedIn: true });
});
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const cart = {
  id: 'cart-1',
  household_id: 'h1',
  discount_code: null,
  expires_at: null,
  lines: [{ id: 'line-1', cart_id: 'cart-1', type: 'package', ref_id: 'pkg-1', quantity: 1 }],
  pricing: {
    lines: [
      {
        type: 'package',
        ref_id: 'pkg-1',
        description: 'Summer package',
        quantity: 1,
        unit_price: 20000,
        line_total: 20000,
        tax_amount: 0,
        discount_amount: 0,
        taxable: false,
      },
    ],
    subtotal: 20000,
    discount_total: 0,
    tax_total: 0,
    total: 20000,
  },
};

const checkout = {
  order: {
    id: 'order-1',
    number: 'SCB-1001',
    household_id: 'h1',
    status: 'pending_payment',
    currency: 'CAD',
    total: 20000,
  },
  redirect_url: 'https://pay.example.com/session/abc',
};

describe('CartPage checkout', () => {
  it('redirects to the hosted payment page (happy path)', async () => {
    server.use(http.get('/api/portal/cart', () => HttpResponse.json(cart)));
    server.use(
      http.post('/api/portal/checkout', () => HttpResponse.json(checkout, { status: 201 })),
    );
    const onRedirect = vi.fn();

    renderWithProviders(<CartPage onRedirect={onRedirect} />, { withAuth: true });

    expect(await screen.findByText('Summer package')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Go to checkout' }));

    await waitFor(() =>
      expect(onRedirect).toHaveBeenCalledWith('https://pay.example.com/session/abc'),
    );
  });

  it('shows a server error and does not redirect when checkout fails', async () => {
    server.use(http.get('/api/portal/cart', () => HttpResponse.json(cart)));
    server.use(
      http.post('/api/portal/checkout', () =>
        HttpResponse.json(
          { error: { code: 'cart_expired', message: 'Your cart has expired' } },
          { status: 422 },
        ),
      ),
    );
    const onRedirect = vi.fn();

    renderWithProviders(<CartPage onRedirect={onRedirect} />, { withAuth: true });

    await screen.findByText('Summer package');
    await userEvent.click(screen.getByRole('button', { name: 'Go to checkout' }));

    expect(await screen.findByText('Your cart has expired')).toBeInTheDocument();
    expect(onRedirect).not.toHaveBeenCalled();
  });
});
