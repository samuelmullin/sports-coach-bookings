import { HttpResponse, http } from 'msw';
import { Route, Routes } from 'react-router-dom';
import { screen } from '@testing-library/react';
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';
import { server } from '@scb/mocks/server';
import { renderWithProviders } from '../../test/render';
import { CoachPlayerDetailPage } from './CoachPlayerDetailPage';
import { SessionRosterPage } from './SessionRosterPage';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const forbidden = () =>
  HttpResponse.json({ error: { code: 'forbidden', message: 'Forbidden' } }, { status: 403 });

describe('coach 403 handling', () => {
  it('shows a friendly state when a player is not on the roster', async () => {
    server.use(http.get('/api/staff/coach/players/:playerId', forbidden));

    renderWithProviders(
      <Routes>
        <Route path="/players/:playerId" element={<CoachPlayerDetailPage />} />
      </Routes>,
      { route: '/players/player-9' },
    );

    expect(await screen.findByText('Not on your roster')).toBeInTheDocument();
    expect(
      screen.getByText('This player is not booked into any of your sessions.'),
    ).toBeInTheDocument();
  });

  it('shows a friendly state when a coach is not assigned to a session', async () => {
    server.use(
      http.get('/api/staff/settings', () =>
        HttpResponse.json({
          currency_locked: false,
          tenant: { currency: 'CAD', timezone: 'America/Toronto' },
        }),
      ),
    );
    server.use(http.get('/api/staff/coach/sessions', () => HttpResponse.json({ data: [] })));
    server.use(http.get('/api/staff/coach/sessions/:sessionId/roster', forbidden));

    renderWithProviders(
      <Routes>
        <Route path="/my-sessions/:sessionId" element={<SessionRosterPage />} />
      </Routes>,
      { route: '/my-sessions/session-9' },
    );

    expect(await screen.findByText('Not on your roster')).toBeInTheDocument();
    expect(
      screen.getByText('You are not assigned to this session, so its roster is not available.'),
    ).toBeInTheDocument();
  });
});
