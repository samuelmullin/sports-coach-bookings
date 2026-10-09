import { HttpResponse, http } from 'msw';
import { screen } from '@testing-library/react';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { server } from '@scb/mocks/server';
import { getPortalExtraHandlers } from '../../../api/extra-handlers';
import { renderWithProviders } from '../../../test/render';
import { PlayersPage } from '../PlayersPage';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
beforeEach(() => server.use(...getPortalExtraHandlers()));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const player = {
  id: 'player-1',
  household_id: 'h1',
  first_name: 'Sky',
  last_name: 'Player',
  date_of_birth: '2015-01-01',
  active: true,
  age: 11,
  is_self: false,
  no_pickup_restrictions: false,
  emergency_contacts: [{ name: 'Pat Parent', phone: '555' }],
};

function useData(waiverPlayers: unknown[]) {
  server.use(
    http.get('/api/portal/players', () => HttpResponse.json({ data: [player] })),
    http.get('/api/portal/waivers/status', () => HttpResponse.json({ players: waiverPlayers })),
  );
}

describe('PlayersPage readiness', () => {
  it('is ready only when the contact is on file and the required waivers are signed', async () => {
    useData([
      {
        player_id: 'player-1',
        waivers: [
          { name: 'Waiver', required: true, signed: true, template_id: 't', version_id: 'v' },
        ],
      },
    ]);
    renderWithProviders(<PlayersPage />);

    expect(await screen.findByText('Ready to book')).toBeInTheDocument();
  });

  it('is not ready while a required waiver is unsigned', async () => {
    useData([
      {
        player_id: 'player-1',
        waivers: [
          { name: 'Waiver', required: true, signed: false, template_id: 't', version_id: 'v' },
        ],
      },
    ]);
    renderWithProviders(<PlayersPage />);

    expect(await screen.findByText('Sky Player')).toBeInTheDocument();
    expect(screen.queryByText('Ready to book')).not.toBeInTheDocument();
  });

  // Regression: a player missing from the waiver status (just added; status not
  // refreshed) used to count as "no waivers required" and showed "Ready to book".
  it('does not show a player as ready when the waiver status does not know them', async () => {
    useData([]);
    renderWithProviders(<PlayersPage />);

    expect(await screen.findByText('Sky Player')).toBeInTheDocument();
    expect(screen.queryByText('Ready to book')).not.toBeInTheDocument();
  });
});
