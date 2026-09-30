import { HttpResponse, http } from 'msw';
import { Route, Routes } from 'react-router-dom';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { mockBrandings } from '@scb/mocks';
import { server } from '@scb/mocks/server';
import { getPortalExtraHandlers } from '../../../api/extra-handlers';
import { renderWithProviders } from '../../../test/render';
import { BrandingProvider } from '../../../theme/branding';
import { PortalLoginPage } from '../../../pages/auth/PortalLoginPage';
import { clearReservationStorage, writeReservation } from '../reservation-store';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
beforeEach(() => {
  server.use(...getPortalExtraHandlers());
  clearReservationStorage();
});
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

function seed() {
  const expiresAt = new Date(Date.now() + 10 * 60_000).toISOString();
  const lastActivityAt = new Date().toISOString();
  writeReservation({
    id: 'res-1',
    token: 'tok-1',
    offeringId: 'off-1',
    optionKind: 'single',
    sessionIds: ['session-1'],
    sessions: [{ session_id: 'session-1', starts_at: '2026-10-01T14:00:00Z' }],
    expiresAt,
    lastActivityAt,
  });
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
  );
}

describe('reservation touch on form submit', () => {
  it('extends the active reservation when the sign-in form is submitted', async () => {
    seed();
    let extendCount = 0;
    server.use(
      http.get('*/api/portal/branding', () => HttpResponse.json(mockBrandings.demo)),
      http.post('*/api/portal/session', () =>
        HttpResponse.json({ customer_user: { id: 'u1' } }, { status: 201 }),
      ),
      http.post('*/api/portal/reservations/res-1/extend', () => {
        extendCount += 1;
        return HttpResponse.json({
          expires_at: new Date(Date.now() + 10 * 60_000).toISOString(),
          last_activity_at: new Date().toISOString(),
        });
      }),
    );

    renderWithProviders(
      <Routes>
        <Route
          path="/login"
          element={
            <BrandingProvider>
              <PortalLoginPage />
            </BrandingProvider>
          }
        />
        <Route path="/account" element={<div>Account screen</div>} />
      </Routes>,
      { route: '/login', withAuth: true },
    );

    await userEvent.type(await screen.findByLabelText('Email'), 'parent@example.com');
    await userEvent.type(screen.getByLabelText('Password'), 'a very long password');
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }));

    await waitFor(() => expect(extendCount).toBe(1));
  });
});
