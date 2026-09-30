import { HttpResponse, http } from 'msw';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { server } from '@scb/mocks/server';
import { getPortalExtraHandlers } from '../../../api/extra-handlers';
import { renderWithProviders } from '../../../test/render';
import { InviteMemberDialog } from '../InviteMemberDialog';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
beforeEach(() => server.use(...getPortalExtraHandlers()));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

describe('InviteMemberDialog', () => {
  it('invites a household member (happy path)', async () => {
    const post = vi.fn(() =>
      HttpResponse.json(
        { invite: { id: 'inv-1', email: 'alex@example.com' }, token: 'tok-1' },
        { status: 201 },
      ),
    );
    server.use(http.post('/api/portal/household/invites', post));

    renderWithProviders(<InviteMemberDialog open onOpenChange={() => undefined} />);

    await userEvent.type(screen.getByLabelText(/Email/), 'alex@example.com');
    await userEvent.type(screen.getByLabelText(/Relationship/), 'Grandparent');
    await userEvent.click(screen.getByRole('button', { name: 'Send invitation' }));

    await waitFor(() => expect(post).toHaveBeenCalledTimes(1));
    expect(await screen.findByText('Invitation sent to alex@example.com')).toBeInTheDocument();
  });

  it('shows a server error when the invite is rejected', async () => {
    server.use(
      http.post('/api/portal/household/invites', () =>
        HttpResponse.json(
          {
            error: {
              code: 'already_member',
              message: 'This person is already in your household',
            },
          },
          { status: 409 },
        ),
      ),
    );

    renderWithProviders(<InviteMemberDialog open onOpenChange={() => undefined} />);

    await userEvent.type(screen.getByLabelText(/Email/), 'alex@example.com');
    await userEvent.click(screen.getByRole('button', { name: 'Send invitation' }));

    expect(
      (await screen.findAllByText('This person is already in your household')).length,
    ).toBeGreaterThan(0);
  });
});
