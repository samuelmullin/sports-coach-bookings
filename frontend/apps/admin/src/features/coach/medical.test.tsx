import { HttpResponse, http } from 'msw';
import { Route, Routes } from 'react-router-dom';
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { server } from '@scb/mocks/server';
import { renderWithProviders } from '../../test/render';
import { CoachPlayerDetailPage } from './CoachPlayerDetailPage';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const playerDetail = {
  player: {
    id: 'player-1',
    first_name: 'Ava',
    last_name: 'Striker',
    age: 12,
    has_medical_info: true,
    profile: { preferred_positions: ['ST'], goals: 'Play rep' },
    emergency_contacts: [],
    authorized_pickups: [],
  },
  feedback: [],
};

describe('coach medical reveal', () => {
  it('requires an explicit reveal and shows the audit notice', async () => {
    server.use(
      http.get('/api/staff/coach/players/:playerId', () => HttpResponse.json(playerDetail)),
    );
    const medical = vi.fn(() =>
      HttpResponse.json({
        id: 'med-1',
        player_id: 'player-1',
        allergies: 'Peanuts',
        conditions: 'Asthma',
        medications: null,
        notes: 'Carries an inhaler',
        has_medical_info: true,
        updated_at: '2026-01-01T00:00:00Z',
      }),
    );
    server.use(http.get('/api/staff/players/:id/medical', medical));

    renderWithProviders(
      <Routes>
        <Route path="/players/:playerId" element={<CoachPlayerDetailPage />} />
      </Routes>,
      { route: '/players/player-1' },
    );

    await userEvent.click(await screen.findByRole('button', { name: 'Reveal medical info' }));

    expect(await screen.findByText('Peanuts')).toBeInTheDocument();
    expect(medical).toHaveBeenCalledTimes(1);
    expect(screen.getByText(/Your access has been recorded in the audit log/i)).toBeInTheDocument();
  });
});
