import { HttpResponse, http } from 'msw';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { server } from '@scb/mocks/server';
import { renderWithProviders } from '../../test/render';
import { MessagingPage } from './MessagingPage';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const settings = {
  currency_locked: false,
  tenant: { currency: 'CAD', timezone: 'America/Toronto' },
};

function setup() {
  server.use(http.get('/api/staff/settings', () => HttpResponse.json(settings)));
  server.use(
    http.get('/api/staff/catalog/venues', () =>
      HttpResponse.json({ data: [{ id: 'venue-1', name: 'Main Dome' }], next_cursor: null }),
    ),
  );
  server.use(
    http.get('/api/staff/catalog/offerings', () =>
      HttpResponse.json({ data: [{ id: 'off-1', name: 'Group Clinic' }], next_cursor: null }),
    ),
  );
  server.use(
    http.get('/api/staff/broadcasts', () =>
      HttpResponse.json({
        data: [
          {
            id: 'b1',
            subject: 'Previously sent',
            body_markdown: 'Hi',
            category: 'operational',
            status: 'sent',
            segment: { venue_ids: [], offering_ids: [], household_ids: [] },
            recipient_count: 10,
            delivered_count: 9,
            open_count: 4,
            scheduled_at: null,
            sent_at: '2026-01-01T00:00:00Z',
            inserted_at: '2026-01-01T00:00:00Z',
          },
        ],
      }),
    ),
  );
  server.use(http.get('/api/staff/broadcasts/recipients', () => HttpResponse.json({ count: 42 })));
}

describe('MessagingPage', () => {
  it('shows a live recipient count and sends a broadcast', async () => {
    setup();
    const post = vi.fn(() =>
      HttpResponse.json(
        {
          id: 'b2',
          subject: 'Hello',
          body_markdown: 'Body',
          category: 'operational',
          status: 'sending',
          segment: { venue_ids: [], offering_ids: [], household_ids: [] },
          recipient_count: 42,
          delivered_count: 0,
          open_count: 0,
          scheduled_at: null,
          sent_at: null,
          inserted_at: '2026-01-01T00:00:00Z',
        },
        { status: 201 },
      ),
    );
    server.use(http.post('/api/staff/broadcasts', post));

    renderWithProviders(<MessagingPage />, { route: '/messaging' });

    expect(await screen.findByText('42 households')).toBeInTheDocument();
    expect(await screen.findByText('Previously sent')).toBeInTheDocument();

    await userEvent.type(screen.getByLabelText(/Subject/), 'Hello');
    await userEvent.type(screen.getByLabelText(/Message/), 'Body');
    expect(screen.getByText('Hello')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Send now' }));
    await waitFor(() => expect(post).toHaveBeenCalledTimes(1));
    expect(await screen.findByText('Broadcast sending')).toBeInTheDocument();
  });

  it('shows an error when the test send fails', async () => {
    setup();
    server.use(
      http.post('/api/staff/broadcasts/test', () =>
        HttpResponse.json(
          { error: { code: 'send_failed', message: 'Test send failed' } },
          { status: 422 },
        ),
      ),
    );

    renderWithProviders(<MessagingPage />, { route: '/messaging' });
    await userEvent.type(await screen.findByLabelText(/Subject/), 'Check');
    await userEvent.click(screen.getByRole('button', { name: 'Send test to me' }));

    expect(await screen.findByText('Test send failed')).toBeInTheDocument();
  });
});
