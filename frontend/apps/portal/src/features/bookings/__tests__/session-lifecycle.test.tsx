import { HttpResponse, http } from 'msw';
import { Route, Routes } from 'react-router-dom';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { server } from '@scb/mocks/server';
import { renderWithProviders } from '../../../test/render';
import { PrivateSessionRequestsPage } from '../PrivateSessionRequestsPage';
import { SessionInvitationsPanel } from '../SessionInvitationsPanel';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const invitation = {
  id: 'invite-1',
  session_id: 'session-1',
  organizer_household_id: 'household-1',
  invitee_household_id: null,
  invitee_player_id: null,
  email: 'friend@example.com',
  status: 'pending',
  payment_mode: 'split',
  seat_status: 'reserved',
  expires_at: '2026-10-05T12:00:00Z',
  accepted_at: null,
  booking_id: null,
  resend_count: 0,
  last_sent_at: '2026-10-03T12:00:00Z',
};

describe('session invitation lifecycle', () => {
  it('shows pending invitations and can resend then revoke them', async () => {
    const resend = vi.fn(() => HttpResponse.json({ ...invitation, resend_count: 1 }));
    const revoke = vi.fn(() => HttpResponse.json({ ...invitation, status: 'cancelled' }));
    server.use(
      http.get('/api/portal/household', () => HttpResponse.json({ id: 'household-1' })),
      http.get('/api/portal/bookings/invitations', () =>
        HttpResponse.json({ data: [invitation], next_cursor: null }),
      ),
      http.post('/api/portal/bookings/invitations/invite-1/resend', resend),
      http.delete('/api/portal/bookings/invitations/invite-1', revoke),
    );

    renderWithProviders(<SessionInvitationsPanel />);

    expect(await screen.findByText('To friend@example.com')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Resend' }));
    await waitFor(() => expect(resend).toHaveBeenCalledOnce());
    await userEvent.click(screen.getByRole('button', { name: 'Revoke' }));
    await waitFor(() => expect(revoke).toHaveBeenCalledOnce());
  });
});

describe('private session request status', () => {
  it('shows an approved request and links to its assigned session', async () => {
    server.use(
      http.get('/api/portal/bookings/private-session-requests', () =>
        HttpResponse.json({
          data: [
            {
              id: 'request-1',
              offering_id: 'offering-1',
              household_id: 'household-1',
              player_count: 4,
              preferred_times: ['2026-10-10T18:00:00Z'],
              notes: 'After school',
              status: 'approved',
              session_id: 'session-4',
              decline_reason: null,
              inserted_at: '2026-10-03T12:00:00Z',
              reviewed_at: '2026-10-04T12:00:00Z',
            },
          ],
          next_cursor: null,
        }),
      ),
      http.get('/api/portal/catalog/offerings', () =>
        HttpResponse.json({ data: [{ id: 'offering-1', name: 'Private Skills' }] }),
      ),
    );

    renderWithProviders(
      <Routes>
        <Route path="/private-session-requests" element={<PrivateSessionRequestsPage />} />
      </Routes>,
      { route: '/private-session-requests' },
    );

    expect(await screen.findByText('Private Skills')).toBeInTheDocument();
    expect(screen.getByText('approved')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'View scheduled session' })).toHaveAttribute(
      'href',
      '/sessions/session-4',
    );
  });
});
