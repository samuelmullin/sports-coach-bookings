import { HttpResponse, http } from 'msw';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { server } from '@scb/mocks/server';
import { renderWithProviders } from '../../test/render';
import { PoliciesPage } from './PoliciesPage';
import { PolicySimulator } from './PolicySimulator';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const settings = {
  currency_locked: false,
  tenant: { currency: 'CAD', timezone: 'America/Toronto' },
};

describe('PoliciesPage', () => {
  it('creates a policy (happy path)', async () => {
    server.use(
      http.get('/api/staff/policies', () => HttpResponse.json({ data: [], next_cursor: null })),
    );
    server.use(http.get('/api/staff/settings', () => HttpResponse.json(settings)));
    const post = vi.fn(() =>
      HttpResponse.json(
        { id: 'policy-1', name: 'Standard', version: 1, rules: {} },
        { status: 201 },
      ),
    );
    server.use(http.post('/api/staff/policies', post));

    renderWithProviders(<PoliciesPage />, { route: '/policies' });
    await userEvent.click(await screen.findByRole('button', { name: 'New policy' }));
    await userEvent.type(await screen.findByLabelText(/^Name/), 'Standard');
    await userEvent.click(screen.getByRole('button', { name: 'Create policy' }));

    await waitFor(() => expect(post).toHaveBeenCalledTimes(1));
    expect(await screen.findByText('Policy created')).toBeInTheDocument();
  });

  it('shows a server error', async () => {
    server.use(
      http.get('/api/staff/policies', () => HttpResponse.json({ data: [], next_cursor: null })),
    );
    server.use(http.get('/api/staff/settings', () => HttpResponse.json(settings)));
    server.use(
      http.post('/api/staff/policies', () =>
        HttpResponse.json(
          {
            error: {
              code: 'invalid',
              message: 'Validation failed',
              details: { fields: { name: ['is invalid'] } },
            },
          },
          { status: 422 },
        ),
      ),
    );

    renderWithProviders(<PoliciesPage />, { route: '/policies' });
    await userEvent.click(await screen.findByRole('button', { name: 'New policy' }));
    await userEvent.type(await screen.findByLabelText(/^Name/), 'Standard');
    await userEvent.click(screen.getByRole('button', { name: 'Create policy' }));

    expect(await screen.findByText('is invalid')).toBeInTheDocument();
  });
});

describe('PolicySimulator', () => {
  it('runs a simulation and shows the outcome', async () => {
    server.use(
      http.get('/api/staff/catalog/offerings', () =>
        HttpResponse.json({ data: [], next_cursor: null }),
      ),
    );
    server.use(http.get('/api/staff/settings', () => HttpResponse.json(settings)));
    const post = vi.fn(() =>
      HttpResponse.json({
        outcome: {
          allowed: true,
          credit_outcome: 'return',
          tier_matched: 48,
          refund_amount: null,
          reason: null,
        },
        snapshot: {},
      }),
    );
    server.use(http.post('/api/staff/policies/simulate', post));

    renderWithProviders(<PolicySimulator policyId="policy-1" />);
    await userEvent.click(await screen.findByRole('button', { name: 'Run simulation' }));

    await waitFor(() => expect(post).toHaveBeenCalledTimes(1));
    expect(await screen.findByTestId('simulator-outcome')).toHaveTextContent('Allowed');
    expect(screen.getByTestId('simulator-outcome')).toHaveTextContent('return');
  });
});
