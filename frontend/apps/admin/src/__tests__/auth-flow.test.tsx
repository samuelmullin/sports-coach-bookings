import { QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { MemoryRouter } from 'react-router-dom';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { createQueryClient } from '@scb/api-client';
import { resetMockSessions, setMockStaffSession } from '@scb/mocks';
import { server } from '@scb/mocks/server';
import '../i18n';
import { AppRoutes } from '../App';
import { StaffAuthProvider } from '../auth/staff-auth';

function renderApp(initialEntries: string[] = ['/']) {
  const queryClient = createQueryClient();
  return render(
    <QueryClientProvider client={queryClient}>
      <StaffAuthProvider>
        <MemoryRouter initialEntries={initialEntries}>
          <AppRoutes />
        </MemoryRouter>
      </StaffAuthProvider>
    </QueryClientProvider>,
  );
}

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

beforeEach(() => resetMockSessions());

describe('admin auth flow', () => {
  it('redirects anonymous staff to login and signs them in', async () => {
    setMockStaffSession({ signedIn: false });
    renderApp(['/']);

    expect(await screen.findByRole('heading', { name: 'Staff sign in' })).toBeInTheDocument();

    await userEvent.type(screen.getByLabelText('Email'), 'owner@demo.test');
    await userEvent.type(screen.getByLabelText('Password'), 'password12345');
    await userEvent.click(screen.getByRole('button', { name: 'Sign in' }));

    await waitFor(() =>
      expect(screen.getByRole('heading', { name: 'Demo Soccer Club' })).toBeInTheDocument(),
    );
    expect(await screen.findByRole('link', { name: 'Dashboard' })).toBeInTheDocument();
  });

  it('gives coaches only their permitted navigation', async () => {
    setMockStaffSession({ signedIn: true, role: 'coach' });
    renderApp(['/']);

    await waitFor(() =>
      expect(screen.queryByRole('link', { name: 'My sessions' })).toBeInTheDocument(),
    );
    expect(screen.getByRole('link', { name: 'Players' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Feedback' })).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'Dashboard' })).not.toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'Customers' })).not.toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'Settings' })).not.toBeInTheDocument();
    expect(screen.getByTestId('staff-role')).toHaveTextContent('coach');
  });

  it('shows the full navigation for owners', async () => {
    setMockStaffSession({ signedIn: true, role: 'owner' });
    renderApp(['/']);

    expect(await screen.findByRole('heading', { name: 'Demo Soccer Club' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Dashboard' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Customers' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Settings' })).toBeInTheDocument();
  });
});
