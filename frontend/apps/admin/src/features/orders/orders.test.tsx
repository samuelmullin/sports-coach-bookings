import { HttpResponse, http } from 'msw';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { server } from '@scb/mocks/server';
import { renderWithProviders } from '../../test/render';
import { RefundDialog } from './RefundDialog';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const settings = {
  currency_locked: false,
  tenant: { currency: 'CAD', timezone: 'America/Toronto' },
};
const lines = [
  {
    id: 'line-1',
    description: 'Summer package',
    line_total: 20000,
    type: 'package',
    refunded_amount: 0,
  },
];

describe('RefundDialog', () => {
  it('refunds all open lines (happy path)', async () => {
    server.use(http.get('/api/staff/settings', () => HttpResponse.json(settings)));
    const post = vi.fn(() => HttpResponse.json({ refunds: [{ id: 'ref-1' }] }));
    server.use(http.post('/api/staff/orders/:id/refund', post));

    renderWithProviders(
      <RefundDialog open onOpenChange={() => undefined} orderId="order-1" lines={lines} />,
    );
    await userEvent.click(screen.getByRole('button', { name: 'Refund' }));

    await waitFor(() => expect(post).toHaveBeenCalledTimes(1));
    expect(await screen.findByText('Refund processed')).toBeInTheDocument();
  });

  it('warns when refunding a package line and offers force', async () => {
    server.use(http.get('/api/staff/settings', () => HttpResponse.json(settings)));
    renderWithProviders(
      <RefundDialog open onOpenChange={() => undefined} orderId="order-1" lines={lines} />,
    );

    await userEvent.click(screen.getByLabelText('Line'));
    await userEvent.click(await screen.findByRole('option', { name: /Summer package/ }));

    expect(await screen.findByText(/Sessions may already have been used/i)).toBeInTheDocument();
    expect(screen.getByLabelText(/Force refund used sessions/)).toBeInTheDocument();
  });

  it('shows a server error', async () => {
    server.use(http.get('/api/staff/settings', () => HttpResponse.json(settings)));
    server.use(
      http.post('/api/staff/orders/:id/refund', () =>
        HttpResponse.json(
          { error: { code: 'invalid', message: 'Payment provider rejected the refund' } },
          { status: 422 },
        ),
      ),
    );

    renderWithProviders(
      <RefundDialog open onOpenChange={() => undefined} orderId="order-1" lines={lines} />,
    );
    await userEvent.click(screen.getByRole('button', { name: 'Refund' }));

    expect(await screen.findByText('Payment provider rejected the refund')).toBeInTheDocument();
  });
});
