import { HttpResponse, http } from 'msw';
import { Route, Routes } from 'react-router-dom';
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { server } from '@scb/mocks/server';
import { renderWithProviders } from '../../test/render';
import { SessionRosterPage } from './SessionRosterPage';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const settings = {
  currency_locked: false,
  tenant: { currency: 'CAD', timezone: 'America/Toronto' },
};

const sessionEntry = {
  session: {
    id: 'session-today',
    offering_id: 'offering-1',
    venue_id: 'venue-1',
    starts_at: '2030-06-01T22:00:00Z',
    ends_at: '2030-06-01T23:00:00Z',
    capacity: 8,
    booked_count: 1,
    seats_left: 7,
    status: 'scheduled',
    visibility: 'public',
    title_override: null,
    series_id: null,
  },
  offering: { id: 'offering-1', name: 'Group Clinic', format: 'group' },
  venue: { id: 'venue-1', name: 'Main Dome', timezone: 'America/Toronto' },
  seats_left: 7,
  bookable: true,
};

const rosterEntry = {
  booking_id: 'booking-1',
  player_id: 'player-1',
  player: {
    id: 'player-1',
    name: 'Ava Striker',
    full_name: 'Ava Striker',
    age: 12,
    preferred_positions: ['ST'],
    has_medical_info: true,
    emergency_contact: { name: 'Priya Striker', relationship: 'Mother', phone: '+1-416-555-0101' },
  },
  status: 'confirmed',
  payment_method: 'credits',
  credits_used: 1,
  hold_expires_at: null,
  feedback: [],
};

function setupBase() {
  server.use(http.get('/api/staff/settings', () => HttpResponse.json(settings)));
  server.use(
    http.get('/api/staff/coach/sessions', () =>
      HttpResponse.json({ data: [sessionEntry], next_cursor: null }),
    ),
  );
  server.use(
    http.get('/api/staff/coach/sessions/:sessionId/roster', () =>
      HttpResponse.json({ data: [rosterEntry] }),
    ),
  );
  server.use(http.get('/api/staff/feedback/skill_tags', () => HttpResponse.json({ data: [] })));
}

function renderRoster() {
  return renderWithProviders(
    <Routes>
      <Route path="/my-sessions/:sessionId" element={<SessionRosterPage />} />
    </Routes>,
    { route: '/my-sessions/session-today' },
  );
}

describe('coach attendance', () => {
  it('marks a player attended (optimistically) and posts the change', async () => {
    setupBase();
    const post = vi.fn((_info: { request: Request }) =>
      HttpResponse.json({
        data: [{ booking_id: 'booking-1', status: 'attended', ok: true, error: null }],
      }),
    );
    server.use(http.post('/api/staff/coach/sessions/:sessionId/attendance', post));

    renderRoster();

    const button = await screen.findByRole('button', { name: 'Mark Ava Striker attended' });
    await userEvent.click(button);

    await waitFor(() => expect(post).toHaveBeenCalledTimes(1));
    expect(await post.mock.calls[0][0].request.json()).toEqual({
      attendance: [{ booking_id: 'booking-1', status: 'attended' }],
    });
    expect(await screen.findByText('Attendance saved')).toBeInTheDocument();
  });

  it('confirms before marking a no-show', async () => {
    setupBase();
    const post = vi.fn(() =>
      HttpResponse.json({
        data: [{ booking_id: 'booking-1', status: 'no_show', ok: true, error: null }],
      }),
    );
    server.use(http.post('/api/staff/coach/sessions/:sessionId/attendance', post));

    renderRoster();

    await userEvent.click(await screen.findByRole('button', { name: 'Mark Ava Striker no-show' }));
    expect(post).not.toHaveBeenCalled();

    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Mark no-show' }));

    await waitFor(() => expect(post).toHaveBeenCalledTimes(1));
  });

  it('shows an error and rolls back when attendance is rejected', async () => {
    setupBase();
    server.use(
      http.post('/api/staff/coach/sessions/:sessionId/attendance', () =>
        HttpResponse.json(
          { error: { code: 'attendance_window_closed', message: 'Attendance window has closed' } },
          { status: 422 },
        ),
      ),
    );

    renderRoster();

    await userEvent.click(await screen.findByRole('button', { name: 'Mark Ava Striker attended' }));

    expect(await screen.findByText('Attendance window has closed')).toBeInTheDocument();
    expect(screen.getByText('Not marked')).toBeInTheDocument();
  });
});
