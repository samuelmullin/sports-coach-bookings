import { HttpResponse, http } from 'msw';
import { Route, Routes } from 'react-router-dom';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { setMockCustomerSession } from '@scb/mocks';
import { server } from '@scb/mocks/server';
import { getPortalExtraHandlers } from '../../../api/extra-handlers';
import { renderWithProviders } from '../../../test/render';
import { ReservationCompletePage } from '../ReservationCompletePage';
import {
  clearReservationStorage,
  writeReservation,
  type StoredReservation,
} from '../reservation-store';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
beforeEach(() => {
  server.use(...getPortalExtraHandlers());
  clearReservationStorage();
  setMockCustomerSession({ signedIn: true });
});
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const player = {
  id: 'player-1',
  household_id: 'h1',
  first_name: 'Sam',
  last_name: 'Player',
  date_of_birth: '2015-01-01',
  active: true,
  age: 11,
  is_self: false,
  no_pickup_restrictions: false,
  emergency_contacts: [{ name: 'Pat Parent', phone: '555' }],
};

function seed(overrides: Partial<StoredReservation> = {}): StoredReservation {
  const reservation: StoredReservation = {
    id: 'res-1',
    token: 'tok-1',
    offeringId: 'off-1',
    optionKind: 'single',
    sessionIds: ['session-1', 'session-2'],
    sessions: [
      {
        session_id: 'session-1',
        starts_at: '2026-10-01T14:00:00Z',
        ends_at: '2026-10-01T15:00:00Z',
      },
      {
        session_id: 'session-2',
        starts_at: '2026-10-08T14:00:00Z',
        ends_at: '2026-10-08T15:00:00Z',
      },
    ],
    expiresAt: new Date(Date.now() + 10 * 60_000).toISOString(),
    lastActivityAt: new Date().toISOString(),
    ...overrides,
  };
  writeReservation(reservation);
  return reservation;
}

function mockShow(reservation: StoredReservation, status = 'active') {
  server.use(
    http.get('*/api/portal/reservations/res-1', () =>
      HttpResponse.json({
        id: reservation.id,
        status,
        offering_id: reservation.offeringId,
        expires_at: reservation.expiresAt,
        last_activity_at: reservation.lastActivityAt,
        sessions: reservation.sessions,
      }),
    ),
  );
}

function renderComplete() {
  return renderWithProviders(
    <Routes>
      <Route path="/reservations/:id/complete" element={<ReservationCompletePage />} />
      <Route path="/cart" element={<div>Cart screen</div>} />
      <Route path="/bookings" element={<div>Bookings screen</div>} />
      <Route path="/players" element={<div>Players screen</div>} />
      <Route path="/schedule" element={<div>Schedule screen</div>} />
    </Routes>,
    { route: '/reservations/res-1/complete', withAuth: true },
  );
}

describe('ReservationCompletePage', () => {
  it('converts with the player assignments and adds paid holds as drop_in cart lines', async () => {
    const reservation = seed();
    mockShow(reservation);
    const convertBodies: Array<{ assignments: unknown[] }> = [];
    const cartBodies: Array<Record<string, unknown>> = [];

    server.use(
      http.get('*/api/portal/players', () => HttpResponse.json({ data: [player] })),
      http.get('*/api/portal/credits', () => HttpResponse.json({ data: [] })),
      http.post('*/api/portal/reservations/res-1/extend', () =>
        HttpResponse.json({
          expires_at: new Date(Date.now() + 10 * 60_000).toISOString(),
          last_activity_at: new Date().toISOString(),
        }),
      ),
      http.post('*/api/portal/reservations/res-1/convert', async ({ request }) => {
        const body = (await request.json()) as { assignments: unknown[] };
        convertBodies.push(body);
        return HttpResponse.json({
          bookings: [
            {
              id: 'booking-1',
              session_id: 'session-1',
              player_id: 'player-1',
              status: 'held',
              payment_method: 'paid',
            },
            {
              id: 'booking-2',
              session_id: 'session-2',
              player_id: 'player-1',
              status: 'held',
              payment_method: 'paid',
            },
          ],
        });
      }),
      http.post('*/api/portal/cart/lines', async ({ request }) => {
        cartBodies.push((await request.json()) as Record<string, unknown>);
        return HttpResponse.json({ id: 'line-1' }, { status: 201 });
      }),
    );

    renderComplete();

    expect(await screen.findByText('Held sessions')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Confirm booking' }));

    await waitFor(() => expect(convertBodies).toHaveLength(1));
    expect(convertBodies[0]?.assignments).toEqual([
      { session_id: 'session-1', player_id: 'player-1', method: 'paid' },
      { session_id: 'session-2', player_id: 'player-1', method: 'paid' },
    ]);

    await waitFor(() => expect(cartBodies).toHaveLength(2));
    expect(cartBodies).toEqual(
      expect.arrayContaining([
        { type: 'drop_in', ref_id: 'booking-1', quantity: 1 },
        { type: 'drop_in', ref_id: 'booking-2', quantity: 1 },
      ]),
    );
    expect(await screen.findByText('Cart screen')).toBeInTheDocument();
  });

  it('shows the abandoned message and re-select action when expired', async () => {
    const reservation = seed({ expiresAt: new Date(Date.now() - 60_000).toISOString() });
    mockShow(reservation, 'expired');

    renderComplete();

    expect(await screen.findByTestId('reservation-abandon-message')).toHaveTextContent(
      'Your reserved session times were released due to inactivity.',
    );
    expect(screen.getByRole('link', { name: 'Select sessions again' })).toHaveAttribute(
      'href',
      '/offerings/off-1/schedule',
    );
  });

  it('treats a bad/unknown token as expired instead of silently continuing', async () => {
    seed();
    server.use(
      http.get('*/api/portal/reservations/res-1', () =>
        HttpResponse.json(
          { error: { code: 'not_found', message: 'Reservation not found' } },
          { status: 404 },
        ),
      ),
    );

    renderComplete();

    expect(await screen.findByTestId('reservation-abandon-message')).toBeInTheDocument();
  });
});
