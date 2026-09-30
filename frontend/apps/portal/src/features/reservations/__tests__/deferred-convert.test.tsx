import { HttpResponse, http } from 'msw';
import { Route, Routes } from 'react-router-dom';
import { screen, waitFor } from '@testing-library/react';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { setMockCustomerSession } from '@scb/mocks';
import { server } from '@scb/mocks/server';
import { getPortalExtraHandlers } from '../../../api/extra-handlers';
import { renderWithProviders } from '../../../test/render';
import { CheckoutReturnPage } from '../../cart/CheckoutReturnPage';
import { clearReservationStorage, writeReservation } from '../reservation-store';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
beforeEach(() => {
  server.use(...getPortalExtraHandlers());
  clearReservationStorage();
  setMockCustomerSession({ signedIn: true });
});
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

describe('deferred pack conversion', () => {
  it('converts a paid pack using the assignments saved at checkout', async () => {
    const expiresAt = new Date(Date.now() + 10 * 60_000).toISOString();
    const lastActivityAt = new Date().toISOString();
    writeReservation({
      id: 'res-1',
      token: 'tok-1',
      offeringId: 'off-1',
      optionKind: 'pack',
      packId: 'pack-3',
      sessionIds: ['session-1'],
      sessions: [{ session_id: 'session-1', starts_at: '2026-10-01T14:00:00Z' }],
      expiresAt,
      lastActivityAt,
      assignments: [{ session_id: 'session-1', player_id: 'player-1', method: 'credits' }],
    });

    const convertBodies: Array<{ assignments: unknown[] }> = [];
    server.use(
      http.get('*/api/portal/reservations/res-1', () =>
        HttpResponse.json({
          id: 'res-1',
          status: 'active',
          offering_id: 'off-1',
          expires_at: expiresAt,
          last_activity_at: lastActivityAt,
          sessions: [{ session_id: 'session-1', starts_at: '2026-10-01T14:00:00Z' }],
        }),
      ),
      http.get('*/api/portal/orders/order-1', () =>
        HttpResponse.json({
          id: 'order-1',
          number: 'SCB-1001',
          household_id: 'h1',
          status: 'paid',
          currency: 'CAD',
          total: 24000,
        }),
      ),
      http.post('*/api/portal/reservations/res-1/convert', async ({ request }) => {
        convertBodies.push((await request.json()) as { assignments: unknown[] });
        return HttpResponse.json({
          bookings: [
            {
              id: 'booking-1',
              session_id: 'session-1',
              player_id: 'player-1',
              status: 'confirmed',
              payment_method: 'credits',
            },
          ],
        });
      }),
    );

    renderWithProviders(
      <Routes>
        <Route path="/checkout/return" element={<CheckoutReturnPage />} />
        <Route path="/bookings" element={<div>Bookings screen</div>} />
      </Routes>,
      { route: '/checkout/return?order_id=order-1', withAuth: true },
    );

    await waitFor(() => expect(convertBodies).toHaveLength(1));
    expect(convertBodies[0]?.assignments).toEqual([
      { session_id: 'session-1', player_id: 'player-1', method: 'credits' },
    ]);
    expect(await screen.findByText('Bookings screen')).toBeInTheDocument();
  });
});
