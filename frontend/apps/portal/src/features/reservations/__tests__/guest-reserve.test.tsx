import { HttpResponse, http } from 'msw';
import { Route, Routes } from 'react-router-dom';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { server } from '@scb/mocks/server';
import { getPortalExtraHandlers } from '../../../api/extra-handlers';
import { renderWithProviders } from '../../../test/render';
import { clearGuestCart, readGuestCart } from '../../cart/guest-cart';
import { GuestReservePage } from '../GuestReservePage';
import { clearReservationStorage, readReservation } from '../reservation-store';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
beforeEach(() => {
  server.use(...getPortalExtraHandlers());
  // Anonymous by default for these guest-flow tests.
  server.use(http.get('/api/portal/account', () => new HttpResponse(null, { status: 401 })));
  clearGuestCart();
  clearReservationStorage();
});
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const offering = {
  id: 'off-1',
  name: 'Private Coaching',
  slug: 'private-coaching',
  format: 'private',
  duration_minutes: 60,
  default_capacity: 4,
  active: true,
  position: 0,
  credit_cost: 1,
  drop_in_price: 9000,
  min_age: null,
  max_age: null,
  taxable: false,
};

const packs = {
  data: [
    {
      id: 'pack-3',
      name: 'Private Coaching 3-Session Pack',
      credit_quantity: 3,
      price: 24000,
      validity_days: 180,
      active: true,
      visible_in_portal: true,
      position: 3,
      offering_ids: ['off-1'],
    },
    {
      id: 'pack-5',
      name: 'Private Coaching 5-Session Pack',
      credit_quantity: 5,
      price: 35000,
      validity_days: 240,
      active: true,
      visible_in_portal: true,
      position: 5,
      offering_ids: ['off-1'],
    },
  ],
  next_cursor: null,
};

function sessionItem(id: string, startsAt: string, endsAt: string) {
  return {
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
      id,
      offering_id: 'off-1',
      starts_at: startsAt,
      ends_at: endsAt,
      capacity: 4,
      seats_left: 4,
      booked_count: 0,
      held_count: 0,
      status: 'scheduled',
    },
    venue: { id: 'venue-1', name: 'Main Field', timezone: 'America/Toronto' },
    coaches: [],
  };
}

const sessions = [
  sessionItem('session-1', '2026-10-01T14:00:00Z', '2026-10-01T15:00:00Z'),
  sessionItem('session-2', '2026-10-08T14:00:00Z', '2026-10-08T15:00:00Z'),
  sessionItem('session-3', '2026-10-15T14:00:00Z', '2026-10-15T15:00:00Z'),
  sessionItem('session-4', '2026-10-22T14:00:00Z', '2026-10-22T15:00:00Z'),
  sessionItem('session-5', '2026-10-29T14:00:00Z', '2026-10-29T15:00:00Z'),
];

function mockBase() {
  server.use(
    http.get('/api/portal/sessions', () => HttpResponse.json({ data: sessions })),
    http.get('/api/portal/catalog/offerings', () => HttpResponse.json({ data: [offering] })),
    http.get('/api/portal/catalog/offerings/off-1/packages', () => HttpResponse.json(packs)),
  );
}

function reservationResponse(sessionIds: string[]) {
  return {
    id: 'res-1',
    token: 'tok-1',
    status: 'active',
    offering_id: 'off-1',
    expires_at: new Date(Date.now() + 10 * 60_000).toISOString(),
    last_activity_at: new Date().toISOString(),
    sessions: sessionIds.map((sessionId) => ({
      session_id: sessionId,
      starts_at: '2026-10-01T14:00:00Z',
      ends_at: '2026-10-01T15:00:00Z',
    })),
  };
}

function renderPage() {
  return renderWithProviders(
    <Routes>
      <Route path="/offerings/:offeringId/schedule" element={<GuestReservePage />} />
      <Route path="/offerings/:offeringId" element={<div>Offering screen</div>} />
      <Route path="/cart" element={<div>Cart screen</div>} />
      <Route path="/register" element={<div>Register screen</div>} />
      <Route path="/reservations/:id/complete" element={<div>Complete screen</div>} />
      <Route path="/login" element={<div>Login screen</div>} />
    </Routes>,
    { route: '/offerings/off-1/schedule', withAuth: true },
  );
}

async function selectFirstTwo() {
  const boxes = await screen.findAllByRole('checkbox');
  await userEvent.click(boxes[0]);
  await userEvent.click(boxes[1]);
}

describe('GuestReservePage', () => {
  it('posts the selected ids, stores the reservation and routes anonymous users to register', async () => {
    mockBase();
    const bodies: Array<Record<string, unknown>> = [];
    server.use(
      http.post('/api/portal/reservations', async ({ request }) => {
        const body = (await request.json()) as { sessions: string[]; offering_id?: string };
        bodies.push(body);
        return HttpResponse.json(reservationResponse(body.sessions), { status: 201 });
      }),
    );

    renderPage();
    await selectFirstTwo();
    await userEvent.click(screen.getByRole('button', { name: 'Reserve & continue' }));

    await waitFor(() => expect(bodies).toHaveLength(1));
    expect(bodies[0]).toEqual({
      sessions: ['session-1', 'session-2'],
      offering_id: 'off-1',
    });

    const stored = await waitFor(() => {
      const value = readReservation();
      expect(value).not.toBeNull();
      return value as NonNullable<ReturnType<typeof readReservation>>;
    });
    expect(stored).toMatchObject({
      id: 'res-1',
      token: 'tok-1',
      offeringId: 'off-1',
      optionKind: 'single',
      sessionIds: ['session-1', 'session-2'],
    });

    expect(await screen.findByText('Register screen')).toBeInTheDocument();
  });

  it('adds the chosen pack to the guest cart when reserving', async () => {
    mockBase();
    server.use(
      http.post('/api/portal/reservations', async ({ request }) => {
        const body = (await request.json()) as { sessions: string[] };
        return HttpResponse.json(reservationResponse(body.sessions), { status: 201 });
      }),
    );

    renderPage();
    // Selecting 3 sessions auto-selects the 3-session pack.
    const boxes = await screen.findAllByRole('checkbox');
    await userEvent.click(boxes[0]);
    await userEvent.click(boxes[1]);
    await userEvent.click(boxes[2]);
    await userEvent.click(screen.getByRole('button', { name: 'Reserve & continue' }));

    await screen.findByText('Register screen');
    const lines = readGuestCart();
    expect(lines).toHaveLength(1);
    expect(lines[0]).toMatchObject({ type: 'package', ref_id: 'pack-3', quantity: 1 });
    expect(readReservation()?.optionKind).toBe('pack');
  });

  it('surfaces a friendly message when a session is full and does not continue', async () => {
    mockBase();
    server.use(
      http.post('/api/portal/reservations', () =>
        HttpResponse.json(
          { error: { code: 'session_full', message: 'This session just filled up' } },
          { status: 409 },
        ),
      ),
    );

    renderPage();
    await selectFirstTwo();
    await userEvent.click(screen.getByRole('button', { name: 'Reserve & continue' }));

    expect(
      await screen.findByText('This session just filled up. Try another time.'),
    ).toBeInTheDocument();
    expect(readReservation()).toBeNull();
    expect(screen.queryByText('Register screen')).not.toBeInTheDocument();
  });

  it('lets the customer choose dates later by buying the pack without a reservation', async () => {
    mockBase();
    let reservationCalls = 0;
    server.use(
      http.post('/api/portal/reservations', () => {
        reservationCalls += 1;
        return HttpResponse.json({ error: { code: 'unexpected' } }, { status: 500 });
      }),
    );

    renderPage();
    // Selecting 3 sessions auto-selects the 3-session pack; buy it and defer.
    const boxes = await screen.findAllByRole('checkbox');
    await userEvent.click(boxes[0]);
    await userEvent.click(boxes[1]);
    await userEvent.click(boxes[2]);
    await userEvent.click(screen.getByRole('button', { name: 'Choose dates later' }));

    expect(await screen.findByText('Cart screen')).toBeInTheDocument();
    expect(reservationCalls).toBe(0);
    expect(readReservation()).toBeNull();
    const lines = readGuestCart();
    expect(lines).toHaveLength(1);
    expect(lines[0]).toMatchObject({ type: 'package', ref_id: 'pack-3', quantity: 1 });
  });

  it('sends signed-in customers straight to the completion step (repeat bookings)', async () => {
    mockBase();
    server.use(
      http.get('/api/portal/account', () =>
        HttpResponse.json({
          customer_user: {
            id: 'cu-1',
            first_name: 'Dana',
            last_name: 'Reyes',
            email: 'dana@example.com',
          },
        }),
      ),
      http.post('/api/portal/cart/lines', () => HttpResponse.json({}, { status: 201 })),
      http.post('/api/portal/reservations', async ({ request }) => {
        const body = (await request.json()) as { sessions: string[] };
        return HttpResponse.json(reservationResponse(body.sessions), { status: 201 });
      }),
    );

    renderPage();
    await selectFirstTwo();
    await userEvent.click(screen.getByRole('button', { name: 'Reserve & continue' }));

    expect(await screen.findByText('Complete screen')).toBeInTheDocument();
    expect(screen.queryByText('Register screen')).not.toBeInTheDocument();
  });

  it('auto-selects the pack that covers 3 selected sessions', async () => {
    mockBase();
    renderPage();

    const boxes = await screen.findAllByRole('checkbox');
    await userEvent.click(boxes[0]);
    await userEvent.click(boxes[1]);

    // 2 drop-ins ($180) are cheaper than the 3-pack ($240) → stays drop-in.
    expect(screen.getByRole('radio', { name: /1 Session -/ })).toBeChecked();

    await userEvent.click(boxes[2]);

    // 3 sessions: the 3-pack ($240) beats 3 drop-ins ($270) → auto-selected.
    expect(screen.getByRole('radio', { name: /3 Sessions -/ })).toBeChecked();
  });

  it('nudges toward the next pack when paying per session', async () => {
    mockBase();
    renderPage();

    const boxes = await screen.findAllByRole('checkbox');
    await userEvent.click(boxes[0]);

    // 3-pack = $240 / 3 = $80 per session vs $90 drop-in → save $10, 2 more.
    expect(await screen.findByTestId('pack-nudge')).toHaveTextContent(
      'Book 2 more sessions and save',
    );

    await userEvent.click(boxes[1]);

    // 2 selected: one more session to reach the 3-pack.
    expect(await screen.findByTestId('pack-nudge')).toHaveTextContent(
      'Book 1 more session and save',
    );
  });

  it('summarises scheduled vs available-later sessions when a pack is not fully used', async () => {
    mockBase();
    renderPage();

    const boxes = await screen.findAllByRole('checkbox');
    await userEvent.click(boxes[0]);
    await userEvent.click(boxes[1]);
    await userEvent.click(boxes[2]);
    await userEvent.click(boxes[3]);

    // 4 selected → cheapest covering option is the 5-pack ($350 < 4×$90).
    expect(screen.getByRole('radio', { name: /5 Sessions -/ })).toBeChecked();
    expect(await screen.findByTestId('schedule-summary')).toHaveTextContent(
      '4 Sessions scheduled. 1 Session will be available to schedule later.',
    );
  });

  it('opens the calendar on the first available session date', async () => {
    mockBase();
    server.use(
      http.get('/api/portal/sessions', () =>
        HttpResponse.json({
          data: [sessionItem('session-future', '2027-06-15T14:00:00Z', '2027-06-15T15:00:00Z')],
        }),
      ),
    );

    renderPage();
    await userEvent.click(await screen.findByRole('button', { name: /Calendar/ }));

    // The calendar header shows the first session's week (2027), not today's.
    expect(await screen.findByText(/2027/)).toBeInTheDocument();
  });
});
