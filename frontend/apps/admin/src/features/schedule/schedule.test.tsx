import { HttpResponse, http } from 'msw';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { server } from '@scb/mocks/server';
import { renderWithProviders } from '../../test/render';
import { SessionFormDrawer } from './SessionFormDrawer';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const settings = {
  currency_locked: false,
  tenant: { currency: 'CAD', timezone: 'America/Toronto' },
};

function setupHandlers() {
  server.use(http.get('/api/staff/settings', () => HttpResponse.json(settings)));
  server.use(
    http.get('/api/staff/catalog/offerings', () =>
      HttpResponse.json({
        data: [
          {
            id: 'off-1',
            name: 'Group Clinic',
            duration_minutes: 60,
            default_capacity: 8,
            format: 'group',
            active: true,
            slug: 'group',
            position: 0,
          },
        ],
        next_cursor: null,
      }),
    ),
  );
  server.use(
    http.get('/api/staff/catalog/venues', () =>
      HttpResponse.json({
        data: [{ id: 'venue-1', name: 'Main Dome', timezone: 'America/Toronto', active: true }],
        next_cursor: null,
      }),
    ),
  );
  server.use(http.get('/api/staff/team', () => HttpResponse.json({ data: [], next_cursor: null })));
}

async function fillRequired() {
  await userEvent.click(await screen.findByLabelText('Offering'));
  await userEvent.click(await screen.findByRole('option', { name: 'Group Clinic' }));
  await userEvent.click(screen.getByLabelText('Venue'));
  await userEvent.click(await screen.findByRole('option', { name: /Main Dome/ }));
}

describe('SessionFormDrawer', () => {
  it('creates a session and shows conflict warnings', async () => {
    setupHandlers();
    const post = vi.fn(() =>
      HttpResponse.json(
        {
          session: { id: 'sess-1', offering_id: 'off-1', venue_id: 'venue-1' },
          warnings: [{ type: 'overlap', message: 'Overlaps another session' }],
        },
        { status: 201 },
      ),
    );
    server.use(http.post('/api/staff/schedule/sessions', post));

    renderWithProviders(
      <SessionFormDrawer open onOpenChange={() => undefined} defaultDate="2026-06-01" />,
    );

    await fillRequired();
    await userEvent.click(screen.getByRole('button', { name: 'Create session' }));

    await waitFor(() => expect(post).toHaveBeenCalledTimes(1));
    expect(await screen.findByTestId('session-warnings')).toHaveTextContent(
      'Overlaps another session',
    );
  });

  it('shows a server error', async () => {
    setupHandlers();
    server.use(
      http.post('/api/staff/schedule/sessions', () =>
        HttpResponse.json(
          {
            error: {
              code: 'invalid',
              message: 'Validation failed',
              details: { fields: { starts_at: ['is in the past'] } },
            },
          },
          { status: 422 },
        ),
      ),
    );

    renderWithProviders(
      <SessionFormDrawer open onOpenChange={() => undefined} defaultDate="2026-06-01" />,
    );

    await fillRequired();
    await userEvent.click(screen.getByRole('button', { name: 'Create session' }));

    expect(await screen.findByText('is in the past')).toBeInTheDocument();
  });

  it('lets the admin hide coach names for the session', async () => {
    setupHandlers();
    let captured: Record<string, unknown> | undefined;
    const post = vi.fn(async ({ request }: { request: Request }) => {
      captured = (await request.json()) as Record<string, unknown>;
      return HttpResponse.json({ session: { id: 'sess-1' }, warnings: [] }, { status: 201 });
    });
    server.use(http.post('/api/staff/schedule/sessions', post));

    renderWithProviders(
      <SessionFormDrawer open onOpenChange={() => undefined} defaultDate="2026-06-01" />,
    );

    await fillRequired();
    await userEvent.click(screen.getByRole('switch', { name: /Show coach names to customers/i }));
    await userEvent.click(screen.getByRole('button', { name: 'Create session' }));

    await waitFor(() => expect(post).toHaveBeenCalledTimes(1));
    expect(captured).toMatchObject({ show_coaches: false });
  });
});
