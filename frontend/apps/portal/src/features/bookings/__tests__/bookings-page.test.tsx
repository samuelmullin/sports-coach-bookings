import { HttpResponse, http } from 'msw';
import { screen } from '@testing-library/react';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { server } from '@scb/mocks/server';
import { getPortalExtraHandlers } from '../../../api/extra-handlers';
import { renderWithProviders } from '../../../test/render';
import { BookingsPage } from '../BookingsPage';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
beforeEach(() => server.use(...getPortalExtraHandlers()));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

function entry(id: string, creditsUsed: number) {
  return {
    booking: {
      id,
      session_id: `s-${id}`,
      player_id: 'p1',
      status: 'confirmed',
      payment_method: 'credits',
      credits_used: creditsUsed,
      paid_amount: 0,
    },
    session: {
      id: `s-${id}`,
      starts_at: '2026-10-20T21:00:00Z',
      ends_at: '2026-10-20T22:00:00Z',
    },
    offering: { id: 'o1', name: 'Group U8-U10' },
  };
}

describe('BookingsPage', () => {
  it('pluralises the sessions used on each booking correctly', async () => {
    server.use(
      http.get('/api/portal/bookings', () =>
        HttpResponse.json({ data: [entry('b1', 1), entry('b2', 2)] }),
      ),
      http.get('/api/portal/players', () =>
        HttpResponse.json({
          data: [{ id: 'p1', first_name: 'Sam', last_name: 'Player', active: true }],
        }),
      ),
    );

    renderWithProviders(<BookingsPage />);

    expect(await screen.findByText(/· 1 session used/)).toBeInTheDocument();
    expect(screen.getByText(/· 2 sessions used/)).toBeInTheDocument();
    expect(screen.queryByText(/1 sessions used/)).not.toBeInTheDocument();
  });
});
