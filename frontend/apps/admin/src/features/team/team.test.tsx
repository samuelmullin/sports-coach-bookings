import { HttpResponse, http } from 'msw';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { server } from '@scb/mocks/server';
import { setMockStaffSession } from '@scb/mocks';
import { renderWithProviders } from '../../test/render';
import { StaffAuthProvider } from '../../auth/staff-auth';
import { TeamPage } from './TeamPage';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const team = {
  data: [
    {
      id: 'membership-1',
      role: 'owner',
      status: 'active',
      display_name: 'Dana Owner',
      staff_user: { email: 'owner@demo.test' },
    },
  ],
  next_cursor: null,
};

function renderTeam() {
  setMockStaffSession({ signedIn: true, role: 'owner' });
  return renderWithProviders(
    <StaffAuthProvider>
      <TeamPage />
    </StaffAuthProvider>,
    { route: '/team' },
  );
}

describe('TeamPage', () => {
  it('invites a member (happy path)', async () => {
    server.use(http.get('/api/staff/team', () => HttpResponse.json(team)));
    server.use(
      http.get('/api/staff/team/invites', () => HttpResponse.json({ data: [], next_cursor: null })),
    );
    const post = vi.fn(() =>
      HttpResponse.json(
        { invite: { id: 'inv-1', email: 'coach@demo.test', role: 'coach' } },
        { status: 201 },
      ),
    );
    server.use(http.post('/api/staff/team/invites', post));

    renderTeam();
    await userEvent.click(await screen.findByRole('button', { name: 'Invite member' }));
    await userEvent.type(await screen.findByLabelText(/^Email/), 'coach@demo.test');
    await userEvent.click(screen.getByRole('button', { name: 'Send invitation' }));

    await waitFor(() => expect(post).toHaveBeenCalledTimes(1));
    expect(await screen.findByText('Invitation sent to coach@demo.test')).toBeInTheDocument();
  });

  it('shows a server error on invite', async () => {
    server.use(http.get('/api/staff/team', () => HttpResponse.json(team)));
    server.use(
      http.get('/api/staff/team/invites', () => HttpResponse.json({ data: [], next_cursor: null })),
    );
    server.use(
      http.post('/api/staff/team/invites', () =>
        HttpResponse.json(
          {
            error: {
              code: 'invalid',
              message: 'Validation failed',
              details: { fields: { email: ['has already been invited'] } },
            },
          },
          { status: 422 },
        ),
      ),
    );

    renderTeam();
    await userEvent.click(await screen.findByRole('button', { name: 'Invite member' }));
    await userEvent.type(await screen.findByLabelText(/^Email/), 'coach@demo.test');
    await userEvent.click(screen.getByRole('button', { name: 'Send invitation' }));

    expect(await screen.findByText('has already been invited')).toBeInTheDocument();
  });
});
