import { HttpResponse, http } from 'msw';
import { Route, Routes } from 'react-router-dom';
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';
import { server } from '@scb/mocks/server';
import { CustomerAuthProvider } from '../../../auth/customer-auth';
import { renderWithProviders } from '../../../test/render';
import { clearGuestCart, readGuestCart } from '../../cart/guest-cart';
import { SessionDetailPage } from '../SessionDetailPage';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const entry = {
  session: {
    id: 'session-1',
    offering_id: 'off-1',
    venue_id: 'ven-1',
    starts_at: '2026-10-01T14:00:00Z',
    ends_at: '2026-10-01T15:00:00Z',
    capacity: 8,
    booked_count: 2,
    held_count: 0,
    seats_left: 6,
    status: 'scheduled',
    visibility: 'public',
    notes_public: 'Bring water and shin pads.',
  },
  offering: {
    id: 'off-1',
    name: 'U10 Skills',
    slug: 'u10-skills',
    description: 'A fun weekly skills session for U10 players.',
    format: 'group',
    duration_minutes: 60,
    default_capacity: 8,
    credit_cost: 1,
    drop_in_price: 2000,
    min_age: null,
    max_age: null,
  },
  venue: { id: 'ven-1', name: 'Field A', timezone: 'America/Toronto' },
  coaches: [],
  seats_left: 6,
  bookable: true,
  not_bookable_reason: null,
  already_booked: false,
  warnings: [],
};

function renderDetail() {
  return renderWithProviders(
    <CustomerAuthProvider>
      <Routes>
        <Route path="/sessions/:sessionId" element={<SessionDetailPage />} />
        <Route path="/register" element={<div>Register screen</div>} />
        <Route path="/login" element={<div>Login screen</div>} />
      </Routes>
    </CustomerAuthProvider>,
    { route: '/sessions/session-1' },
  );
}

describe('SessionDetailPage', () => {
  it('shows the session and a register call to action for anonymous visitors', async () => {
    server.use(
      http.get('/api/portal/account', () => new HttpResponse(null, { status: 401 })),
      http.get('/api/portal/sessions/session-1', () => HttpResponse.json(entry)),
    );

    renderDetail();

    expect(await screen.findByRole('heading', { name: /U10 Skills/ })).toBeInTheDocument();
    expect(screen.getByText(/A fun weekly skills session for U10 players/)).toBeInTheDocument();
    expect(screen.getByText(/Bring water and shin pads/)).toBeInTheDocument();
    expect(screen.getByText(/6 of 8 seats left/)).toBeInTheDocument();

    const cta = screen.getByRole('link', { name: /Create an account/i });
    expect(cta).toHaveAttribute('href', '/register');

    await userEvent.click(cta);
    expect(await screen.findByText('Register screen')).toBeInTheDocument();
  });

  it('lets an anonymous visitor add a paid drop-in to the guest cart', async () => {
    clearGuestCart();
    server.use(
      http.get('/api/portal/account', () => new HttpResponse(null, { status: 401 })),
      http.get('/api/portal/sessions/session-1', () => HttpResponse.json(entry)),
    );

    renderDetail();

    await userEvent.click(await screen.findByRole('button', { name: 'Add to cart' }));

    expect(await screen.findByText('Added to cart')).toBeInTheDocument();
    const lines = readGuestCart();
    expect(lines).toHaveLength(1);
    expect(lines[0]).toMatchObject({
      type: 'drop_in',
      ref_id: 'session-1',
      snapshot: { title: 'U10 Skills', sessionId: 'session-1', venueName: 'Field A' },
    });
  });

  it('shows a not-found state when the session is unavailable', async () => {
    server.use(
      http.get('/api/portal/account', () => new HttpResponse(null, { status: 401 })),
      http.get('/api/portal/sessions/missing', () =>
        HttpResponse.json({ error: { code: 'not_found' } }, { status: 404 }),
      ),
    );

    renderWithProviders(
      <CustomerAuthProvider>
        <Routes>
          <Route path="/sessions/:sessionId" element={<SessionDetailPage />} />
        </Routes>
      </CustomerAuthProvider>,
      { route: '/sessions/missing' },
    );

    expect(await screen.findByText(/no longer available/i)).toBeInTheDocument();
  });
});
