import { HttpResponse, http } from 'msw';
import { screen } from '@testing-library/react';
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';
import { server } from '@scb/mocks/server';
import { renderWithProviders } from '../../test/render';
import { CustomersPage } from './CustomersPage';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

describe('CustomersPage households', () => {
  // Rows were a bare household name, so several "Reyes Household" rows were
  // indistinguishable. Each row now shows who the household is.
  it('shows each household with its primary contact and member count', async () => {
    server.use(
      http.get('/api/staff/households', () =>
        HttpResponse.json({
          data: [
            {
              id: 'h1',
              name: 'Reyes Household',
              member_count: 2,
              primary_contact: { name: 'Dana Reyes', email: 'dana@example.com' },
            },
            { id: 'h2', name: null, member_count: 0, primary_contact: null },
          ],
          next_cursor: null,
        }),
      ),
    );

    renderWithProviders(<CustomersPage />);

    expect(await screen.findByText('Dana Reyes')).toBeInTheDocument();
    expect(screen.getByText('dana@example.com')).toBeInTheDocument();
    expect(screen.getByText('2')).toBeInTheDocument();
    expect(screen.getByText('Unnamed household')).toBeInTheDocument();
  });
});
