import { QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { HttpResponse, delay, http } from 'msw';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { createQueryClient } from '@scb/api-client';
import { mockBrandings, resetMockSessions, setMockCustomerSession } from '@scb/mocks';
import { server } from '@scb/mocks/server';
import '../i18n';
import { AppRoutes } from '../App';
import { CustomerAuthProvider } from '../auth/customer-auth';
import { BrandingProvider } from '../theme/branding';

function renderPortal(initialEntries: string[] = ['/']) {
  const queryClient = createQueryClient();
  return render(
    <QueryClientProvider client={queryClient}>
      <BrandingProvider>
        <CustomerAuthProvider>
          <MemoryRouter initialEntries={initialEntries}>
            <AppRoutes />
          </MemoryRouter>
        </CustomerAuthProvider>
      </BrandingProvider>
    </QueryClientProvider>,
  );
}

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

beforeEach(() => {
  resetMockSessions();
  setMockCustomerSession({ signedIn: false });
  document.documentElement.removeAttribute('style');
});

describe('portal branding', () => {
  it('shows a neutral splash before branding loads, then applies tenant theme', async () => {
    server.use(
      http.get('/api/portal/branding', async () => {
        await delay(40);
        return HttpResponse.json(mockBrandings.united);
      }),
    );

    renderPortal(['/']);

    expect(screen.getByTestId('scb-splash')).toBeInTheDocument();
    expect(screen.queryByTestId('tenant-logo')).not.toBeInTheDocument();

    const logo = await screen.findByTestId('tenant-logo');
    expect(logo).toHaveAttribute('alt', 'United Coaching');
    await waitFor(() =>
      expect(document.documentElement.style.getPropertyValue('--color-primary')).toBe('#7c3aed'),
    );
    expect(document.title).toBe('United Coaching');
  });

  it('renders a second tenant with its own theme', async () => {
    server.use(http.get('/api/portal/branding', () => HttpResponse.json(mockBrandings.demo)));
    renderPortal(['/']);

    expect((await screen.findAllByText('Demo Soccer Club')).length).toBeGreaterThan(0);
    await waitFor(() =>
      expect(document.documentElement.style.getPropertyValue('--color-primary')).toBe('#15803d'),
    );
  });

  it('exposes public navigation for anonymous visitors', async () => {
    renderPortal(['/']);
    expect(
      await screen.findByRole('heading', { name: 'Book coaching sessions with ease' }),
    ).toBeInTheDocument();
    expect(screen.getAllByRole('link', { name: 'Schedule' }).length).toBeGreaterThan(0);
    expect(screen.getAllByRole('link', { name: 'Packages' }).length).toBeGreaterThan(0);
    expect(screen.getAllByRole('link', { name: 'Shop' }).length).toBeGreaterThan(0);
  });

  it('redirects unauthenticated users from protected routes to login', async () => {
    renderPortal(['/account']);
    expect(await screen.findByRole('heading', { name: 'Sign in' })).toBeInTheDocument();
  });
});
