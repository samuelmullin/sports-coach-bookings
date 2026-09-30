import { HttpResponse, http } from 'msw';
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { server } from '@scb/mocks/server';
import { renderWithProviders } from '../../test/render';
import { StockPage } from './StockPage';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const settings = {
  currency_locked: false,
  tenant: { currency: 'CAD', timezone: 'America/Toronto' },
};

function setup() {
  server.use(http.get('/api/staff/settings', () => HttpResponse.json(settings)));
  server.use(
    http.get('/api/staff/inventory/products', () =>
      HttpResponse.json({
        data: [{ id: 'prod-1', name: 'Home Kit', active: true, visible_in_portal: true }],
        next_cursor: null,
      }),
    ),
  );
  server.use(
    http.get('/api/staff/inventory/products/:productId/variants', () =>
      HttpResponse.json({
        data: [{ id: 'var-1', sku: 'KIT-YM', price: 4500, product_id: 'prod-1', active: true }],
        next_cursor: null,
      }),
    ),
  );
  server.use(
    http.get('/api/staff/inventory/stock_levels', () =>
      HttpResponse.json({
        data: [{ id: 'stock-1', variant_id: 'var-1', on_hand: 3, reserved: 1, available: 2 }],
        next_cursor: null,
      }),
    ),
  );
}

describe('StockPage', () => {
  it('receives stock (happy path)', async () => {
    setup();
    const post = vi.fn(() =>
      HttpResponse.json({ id: 'stock-1', variant_id: 'var-1', on_hand: 13 }, { status: 201 }),
    );
    server.use(http.post('/api/staff/inventory/variants/:id/stock/receive', post));

    renderWithProviders(<StockPage />, { route: '/inventory/stock' });
    await userEvent.click(await screen.findByRole('button', { name: 'Receive' }));

    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Receive' }));

    await waitFor(() => expect(post).toHaveBeenCalledTimes(1));
    expect(await screen.findByText('Stock received')).toBeInTheDocument();
  });

  it('shows a server error when receiving stock', async () => {
    setup();
    server.use(
      http.post('/api/staff/inventory/variants/:id/stock/receive', () =>
        HttpResponse.json(
          { error: { code: 'invalid', message: 'Quantity must be positive' } },
          { status: 422 },
        ),
      ),
    );

    renderWithProviders(<StockPage />, { route: '/inventory/stock' });
    await userEvent.click(await screen.findByRole('button', { name: 'Receive' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Receive' }));

    expect(await screen.findByText('Quantity must be positive')).toBeInTheDocument();
  });
});
