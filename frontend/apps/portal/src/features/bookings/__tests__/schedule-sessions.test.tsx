import { HttpResponse, http } from 'msw';
import { Route, Routes } from 'react-router-dom';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { setMockCustomerSession } from '@scb/mocks';
import { server } from '@scb/mocks/server';
import { getPortalExtraHandlers } from '../../../api/extra-handlers';
import { renderWithProviders } from '../../../test/render';
import { ScheduleSessionsPage } from '../ScheduleSessionsPage';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
beforeEach(() => {
  server.use(...getPortalExtraHandlers());
  setMockCustomerSession({ signedIn: true });
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

const otherOffering = {
  ...offering,
  id: 'off-2',
  name: 'Group Training',
  slug: 'group-training',
  format: 'group',
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
];

type Credit = { offering_id: string; amount: number };

function mockBase({ credits = [{ offering_id: 'off-1', amount: 3 }] as Credit[] } = {}) {
  server.use(
    http.get('/api/portal/sessions', () => HttpResponse.json({ data: sessions })),
    http.get('/api/portal/catalog/offerings', () =>
      HttpResponse.json({ data: [offering, otherOffering] }),
    ),
    http.get('/api/portal/players', () => HttpResponse.json({ data: [player] })),
    http.get('/api/portal/credits', () => HttpResponse.json({ data: credits })),
  );
}

function renderPage(route = '/offerings/off-1/schedule') {
  return renderWithProviders(
    <Routes>
      <Route path="/offerings/:offeringId/schedule" element={<ScheduleSessionsPage />} />
      <Route path="/offerings/:offeringId" element={<div>Offering screen</div>} />
      <Route path="/cart" element={<div>Cart screen</div>} />
      <Route path="/credits" element={<div>Credits screen</div>} />
      <Route path="/packages" element={<div>Packages screen</div>} />
    </Routes>,
    { route, withAuth: true },
  );
}

async function selectPlayer() {
  await userEvent.click(await screen.findByRole('combobox', { name: 'Player' }));
  await userEvent.click(await screen.findByRole('option', { name: /Sam Player/ }));
}

async function selectFirstTwo() {
  const boxes = await screen.findAllByRole('checkbox');
  await userEvent.click(boxes[0]);
  await userEvent.click(boxes[1]);
}

describe('ScheduleSessionsPage', () => {
  it('books two selected sessions with credits', async () => {
    mockBase();
    const bodies: Array<Record<string, unknown>> = [];
    server.use(
      http.post('/api/portal/bookings', async ({ request }) => {
        bodies.push((await request.json()) as Record<string, unknown>);
        return HttpResponse.json(
          { id: 'booking-1', status: 'confirmed', payment_method: 'credits' },
          { status: 201 },
        );
      }),
    );

    renderPage();
    await selectPlayer();
    await selectFirstTwo();

    expect(await screen.findByText('2 sessions selected')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Confirm bookings' }));

    await waitFor(() => expect(bodies).toHaveLength(2));
    expect(bodies).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          player_id: 'player-1',
          session_id: 'session-1',
          method: 'credits',
        }),
        expect.objectContaining({
          player_id: 'player-1',
          session_id: 'session-2',
          method: 'credits',
        }),
      ]),
    );
    expect(await screen.findAllByText(/^Booked:/)).toHaveLength(2);
  });

  it('holds each paid session and adds a drop-in cart line per hold', async () => {
    mockBase({ credits: [] });
    const bookingBodies: Array<Record<string, unknown>> = [];
    const lineBodies: Array<Record<string, unknown>> = [];
    let holds = 0;
    server.use(
      http.post('/api/portal/bookings', async ({ request }) => {
        bookingBodies.push((await request.json()) as Record<string, unknown>);
        holds += 1;
        return HttpResponse.json(
          { id: `hold-${holds}`, status: 'held', payment_method: 'paid' },
          { status: 201 },
        );
      }),
      http.post('/api/portal/cart/lines', async ({ request }) => {
        lineBodies.push((await request.json()) as Record<string, unknown>);
        return HttpResponse.json(
          { id: 'line-1', type: 'drop_in', ref_id: 'hold-1', quantity: 1 },
          { status: 201 },
        );
      }),
    );

    renderPage();
    await selectPlayer();
    await selectFirstTwo();
    await userEvent.click(screen.getByRole('button', { name: 'Confirm bookings' }));

    await waitFor(() => expect(bookingBodies).toHaveLength(2));
    expect(bookingBodies.every((body) => body.method === 'paid')).toBe(true);
    await waitFor(() => expect(lineBodies).toHaveLength(2));
    expect(lineBodies).toEqual(
      expect.arrayContaining([
        { type: 'drop_in', ref_id: 'hold-1', quantity: 1 },
        { type: 'drop_in', ref_id: 'hold-2', quantity: 1 },
      ]),
    );
    expect(await screen.findByText('Cart screen')).toBeInTheDocument();
  });

  it('surfaces a per-session failure and keeps the successful booking', async () => {
    mockBase();
    const bodies: Array<Record<string, unknown>> = [];
    server.use(
      http.post('/api/portal/bookings', async ({ request }) => {
        const body = (await request.json()) as Record<string, unknown>;
        bodies.push(body);
        if (body.session_id === 'session-2') {
          return HttpResponse.json(
            { error: { code: 'session_full', message: 'This session just filled up' } },
            { status: 422 },
          );
        }
        return HttpResponse.json(
          { id: 'booking-1', status: 'confirmed', payment_method: 'credits' },
          { status: 201 },
        );
      }),
    );

    renderPage();
    await selectPlayer();
    await selectFirstTwo();
    await userEvent.click(screen.getByRole('button', { name: 'Confirm bookings' }));

    await waitFor(() => expect(bodies).toHaveLength(2));
    expect(
      await screen.findByText('This session just filled up. Try another time.'),
    ).toBeInTheDocument();
    expect(await screen.findAllByText(/^Booked:/)).toHaveLength(1);
    expect(screen.getByText(/^Not booked:/)).toBeInTheDocument();
    // The failed session stays selected so the customer can retry it.
    expect(screen.getByRole('checkbox', { checked: true })).toBeInTheDocument();
  });

  it("navigates to credits for 'choose dates later' when credits exist", async () => {
    mockBase();
    renderPage();

    const link = await screen.findByRole('link', { name: /choose dates later/ });
    expect(link).toHaveAttribute('href', '/credits');
    await userEvent.click(link);

    expect(await screen.findByText('Credits screen')).toBeInTheDocument();
  });

  it("navigates to packages for 'choose dates later' when there are no credits", async () => {
    mockBase({ credits: [] });
    renderPage();

    const link = await screen.findByRole('link', { name: /choose dates later/ });
    expect(link).toHaveAttribute('href', '/packages');
  });

  it('disables confirmation when the selection exceeds available credits', async () => {
    mockBase({ credits: [{ offering_id: 'off-1', amount: 1 }] });
    renderPage();
    await selectPlayer();
    await selectFirstTwo();

    expect(screen.getByRole('button', { name: 'Confirm bookings' })).toBeDisabled();
    expect(await screen.findByText(/only 1 session is available/)).toBeInTheDocument();

    const boxes = screen.getAllByRole('checkbox');
    await userEvent.click(boxes[1]);

    await waitFor(() =>
      expect(screen.getByRole('button', { name: 'Confirm bookings' })).toBeEnabled(),
    );
  });
});
