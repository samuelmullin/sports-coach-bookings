import { HttpResponse, http } from 'msw';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { server } from '@scb/mocks/server';
import { renderWithProviders } from '../../../test/render';
import { ReservationBanner } from '../ReservationBanner';
import {
  clearReservationStorage,
  writeReservation,
  type StoredReservation,
} from '../reservation-store';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
beforeEach(() => clearReservationStorage());
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

function seed(overrides: Partial<StoredReservation> = {}): StoredReservation {
  const reservation: StoredReservation = {
    id: 'res-1',
    token: 'tok-1',
    offeringId: 'off-1',
    optionKind: 'single',
    sessionIds: ['session-1'],
    sessions: [
      {
        session_id: 'session-1',
        starts_at: '2026-10-01T14:00:00Z',
        ends_at: '2026-10-01T15:00:00Z',
      },
    ],
    expiresAt: new Date(Date.now() + 10 * 60_000).toISOString(),
    lastActivityAt: new Date(Date.now() - 9 * 60_000).toISOString(),
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

describe('ReservationBanner', () => {
  it('warns after ~8 minutes idle and extends when "Need more time" is pressed', async () => {
    const reservation = seed();
    mockShow(reservation);
    let extendCount = 0;
    server.use(
      http.post('*/api/portal/reservations/res-1/extend', () => {
        extendCount += 1;
        return HttpResponse.json({
          expires_at: new Date(Date.now() + 10 * 60_000).toISOString(),
          last_activity_at: new Date().toISOString(),
        });
      }),
    );

    renderWithProviders(<ReservationBanner />);

    const button = await screen.findByRole('button', { name: 'Need more time' });
    expect(screen.getByText(/Still deciding/)).toBeInTheDocument();

    await userEvent.click(button);

    await waitFor(() => expect(extendCount).toBe(1));
    await waitFor(() =>
      expect(screen.queryByRole('button', { name: 'Need more time' })).not.toBeInTheDocument(),
    );
  });

  it('switches to an expired state with a re-select action', async () => {
    const reservation = seed({ expiresAt: new Date(Date.now() - 60_000).toISOString() });
    mockShow(reservation, 'expired');

    renderWithProviders(<ReservationBanner />);

    expect(await screen.findByTestId('reservation-banner')).toHaveTextContent(
      'Your reserved session times were released due to inactivity.',
    );
    expect(screen.getByRole('link', { name: 'Select sessions again' })).toHaveAttribute(
      'href',
      '/offerings/off-1/schedule',
    );
  });
});
