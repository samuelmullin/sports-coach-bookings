import { HttpResponse, http } from 'msw';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { server } from '@scb/mocks/server';
import { renderWithProviders } from '../../test/render';
import { VenuesPage } from './VenuesPage';
import { PackagesPage } from './PackagesPage';
import { DiscountsPage } from './DiscountsPage';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const emptyList = { data: [], next_cursor: null };

describe('VenuesPage', () => {
  it('creates a venue (happy path)', async () => {
    server.use(http.get('/api/staff/catalog/venues', () => HttpResponse.json(emptyList)));
    server.use(
      http.get('/api/staff/settings', () =>
        HttpResponse.json({
          currency_locked: false,
          tenant: { currency: 'CAD', timezone: 'America/Toronto' },
        }),
      ),
    );
    const post = vi.fn(() =>
      HttpResponse.json(
        { id: 'venue-1', name: 'Main Dome', timezone: 'America/Toronto', active: true },
        { status: 201 },
      ),
    );
    server.use(http.post('/api/staff/catalog/venues', post));

    renderWithProviders(<VenuesPage />);
    await userEvent.click(await screen.findByRole('button', { name: 'Add venue' }));
    await userEvent.type(await screen.findByLabelText(/^Name/), 'Main Dome');
    await userEvent.click(screen.getByRole('button', { name: 'Save venue' }));

    await waitFor(() => expect(post).toHaveBeenCalledTimes(1));
    expect(await screen.findByText('Venue created')).toBeInTheDocument();
  });

  it('shows a server error', async () => {
    server.use(http.get('/api/staff/catalog/venues', () => HttpResponse.json(emptyList)));
    server.use(
      http.get('/api/staff/settings', () =>
        HttpResponse.json({
          currency_locked: false,
          tenant: { currency: 'CAD', timezone: 'America/Toronto' },
        }),
      ),
    );
    server.use(
      http.post('/api/staff/catalog/venues', () =>
        HttpResponse.json(
          {
            error: {
              code: 'invalid',
              message: 'Validation failed',
              details: { fields: { name: ['has already been taken'] } },
            },
          },
          { status: 422 },
        ),
      ),
    );

    renderWithProviders(<VenuesPage />);
    await userEvent.click(await screen.findByRole('button', { name: 'Add venue' }));
    await userEvent.type(await screen.findByLabelText(/^Name/), 'Main Dome');
    await userEvent.click(screen.getByRole('button', { name: 'Save venue' }));

    expect(await screen.findByText('has already been taken')).toBeInTheDocument();
  });
});

describe('PackagesPage', () => {
  const settingsHandler = http.get('/api/staff/settings', () =>
    HttpResponse.json({
      currency_locked: false,
      tenant: { currency: 'CAD', timezone: 'America/Toronto' },
    }),
  );

  it('validates a required name before submitting', async () => {
    server.use(http.get('/api/staff/catalog/packages', () => HttpResponse.json(emptyList)));
    server.use(http.get('/api/staff/catalog/offerings', () => HttpResponse.json(emptyList)));
    server.use(settingsHandler);

    renderWithProviders(<PackagesPage />);
    await userEvent.click(await screen.findByRole('button', { name: 'Add package' }));
    await userEvent.click(screen.getByRole('button', { name: 'Save package' }));

    expect(await screen.findByText('Name is required')).toBeInTheDocument();
  });

  it('prefills eligible offerings when editing and sends them on update', async () => {
    server.use(
      http.get('/api/staff/catalog/packages', () =>
        HttpResponse.json({
          data: [
            {
              id: 'pack-1',
              name: 'Group Pack',
              description: null,
              credit_quantity: 5,
              price: 18000,
              validity_days: 240,
              per_household_limit: null,
              visible_in_portal: true,
              taxable: true,
              active: true,
              position: 0,
              offering_ids: ['off-1'],
            },
          ],
          next_cursor: null,
        }),
      ),
    );
    server.use(
      http.get('/api/staff/catalog/offerings', () =>
        HttpResponse.json({
          data: [{ id: 'off-1', name: 'Group U11-U14' }],
          next_cursor: null,
        }),
      ),
    );
    server.use(settingsHandler);

    let updateBody: Record<string, unknown> | undefined;

    server.use(
      http.patch('/api/staff/catalog/packages/pack-1', async ({ request }) => {
        updateBody = (await request.json()) as Record<string, unknown>;
        return HttpResponse.json({ id: 'pack-1' });
      }),
    );

    renderWithProviders(<PackagesPage />);
    await userEvent.click(await screen.findByRole('button', { name: 'Edit' }));

    expect(await screen.findByRole('checkbox', { name: 'Group U11-U14' })).toBeChecked();

    await userEvent.click(screen.getByRole('button', { name: 'Save package' }));

    await waitFor(() => expect(updateBody).toBeDefined());
    expect(updateBody).toMatchObject({ offering_ids: ['off-1'] });
  });
});

describe('DiscountsPage', () => {
  it('creates a discount (happy path)', async () => {
    server.use(http.get('/api/staff/catalog/discounts', () => HttpResponse.json(emptyList)));
    server.use(
      http.get('/api/staff/settings', () =>
        HttpResponse.json({
          currency_locked: false,
          tenant: { currency: 'CAD', timezone: 'America/Toronto' },
        }),
      ),
    );
    const post = vi.fn(() =>
      HttpResponse.json(
        {
          id: 'disc-1',
          code: 'SUMMER10',
          kind: 'percent',
          value: 10,
          applies_to: 'all',
          active: true,
        },
        { status: 201 },
      ),
    );
    server.use(http.post('/api/staff/catalog/discounts', post));

    renderWithProviders(<DiscountsPage />);
    await userEvent.click(await screen.findByRole('button', { name: 'Add discount' }));
    await userEvent.type(await screen.findByLabelText('Code'), 'SUMMER10');
    await userEvent.click(screen.getByRole('button', { name: 'Save discount' }));

    await waitFor(() => expect(post).toHaveBeenCalledTimes(1));
    expect(await screen.findByText('Discount created')).toBeInTheDocument();
  });
});
