import { HttpResponse, http } from 'msw';
import { Route, Routes } from 'react-router-dom';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { server } from '@scb/mocks/server';
import { getPortalExtraHandlers } from '../../../api/extra-handlers';
import { renderWithProviders } from '../../../test/render';
import { BookingFlowPage } from '../BookingFlowPage';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
beforeEach(() => server.use(...getPortalExtraHandlers()));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const offering = {
  id: 'off-1',
  name: 'Private Coaching',
  slug: 'private-coaching',
  format: 'private',
  duration_minutes: 60,
  default_capacity: 1,
  active: true,
  position: 0,
  credit_cost: 1,
  drop_in_price: 9000,
  min_age: null,
  max_age: null,
  taxable: false,
};

const sessionItem = {
  bookable: true,
  already_booked: false,
  seats_left: 4,
  offering: {
    id: 'off-1',
    name: 'Private Coaching',
    slug: 'private-coaching',
    format: 'private',
    duration_minutes: 60,
    default_capacity: 4,
    min_age: null,
    max_age: null,
  },
  session: {
    id: 'session-1',
    offering_id: 'off-1',
    starts_at: '2026-10-01T14:00:00Z',
    ends_at: '2026-10-01T15:00:00Z',
    capacity: 4,
    seats_left: 4,
    booked_count: 0,
    held_count: 0,
    status: 'scheduled',
  },
  venue: { id: 'venue-1', name: 'Main Field', timezone: 'America/Toronto' },
  coaches: [{ membership_id: 'coach-1', display_name: 'Coach Dana', role: 'coach' }],
};

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

const waivers = {
  players: [
    {
      player_id: 'player-1',
      waivers: [
        {
          name: 'Participation waiver',
          required: true,
          signed: true,
          template_id: 't1',
          version_id: 'v1',
        },
      ],
    },
  ],
};

const booking = {
  id: 'booking-1',
  session_id: 'session-1',
  player_id: 'player-1',
  status: 'confirmed',
  payment_method: 'credits',
  credits_used: 1,
  paid_amount: 0,
};

function renderFlow() {
  return renderWithProviders(
    <Routes>
      <Route path="/book/:sessionId" element={<BookingFlowPage />} />
    </Routes>,
    { route: '/book/session-1' },
  );
}

function useBookingData() {
  server.use(
    http.get('/api/portal/sessions', () => HttpResponse.json({ data: [sessionItem] })),
    http.get('/api/portal/catalog/offerings', () => HttpResponse.json({ data: [offering] })),
    http.get('/api/portal/players', () => HttpResponse.json({ data: [player] })),
    http.get('/api/portal/credits', () =>
      HttpResponse.json({ data: [{ offering_id: 'off-1', amount: 3 }] }),
    ),
    http.get('/api/portal/waivers/status', () => HttpResponse.json(waivers)),
  );
}

async function selectPlayer() {
  await userEvent.click(await screen.findByRole('combobox', { name: 'Player' }));
  await userEvent.click(await screen.findByRole('option', { name: /Sam Player/ }));
}

describe('BookingFlowPage', () => {
  it('books a session with credits (happy path)', async () => {
    useBookingData();
    const post = vi.fn(() => HttpResponse.json(booking, { status: 201 }));
    server.use(http.post('/api/portal/bookings', post));

    renderFlow();
    await selectPlayer();

    expect(await screen.findByText('Required waivers signed')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Confirm booking' }));

    await waitFor(() => expect(post).toHaveBeenCalledTimes(1));
    expect(await screen.findByText("You're booked!")).toBeInTheDocument();
    expect(screen.getByText(/Sam is booked into Private Coaching/)).toBeInTheDocument();
  });

  it('does not treat a player missing from the waiver status as signed', async () => {
    useBookingData();
    // A just-added player is not in the (cached) household waiver status yet.
    server.use(http.get('/api/portal/waivers/status', () => HttpResponse.json({ players: [] })));

    renderFlow();
    await selectPlayer();

    expect(await screen.findByText('Required waivers signed')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Confirm booking' })).toBeDisabled();
  });

  it('shows a server error when credits are insufficient', async () => {
    useBookingData();
    server.use(
      http.post('/api/portal/bookings', () =>
        HttpResponse.json(
          {
            error: {
              code: 'insufficient_credits',
              message: 'Not enough credits',
            },
          },
          { status: 422 },
        ),
      ),
    );

    renderFlow();
    await selectPlayer();
    await userEvent.click(screen.getByRole('button', { name: 'Confirm booking' }));

    expect(
      await screen.findByText('This player does not have enough eligible sessions.'),
    ).toBeInTheDocument();
  });
});
