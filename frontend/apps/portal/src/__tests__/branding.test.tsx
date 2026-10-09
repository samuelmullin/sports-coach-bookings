import { QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
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

    const [logo] = await screen.findAllByTestId('tenant-logo');
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

  it('renders published website content and applies its search metadata', async () => {
    server.use(
      http.get('/api/portal/website', () =>
        HttpResponse.json({
          enabled: true,
          published_at: '2026-10-03T12:00:00Z',
          content: {
            hero: {
              eyebrow: 'J Starz Basketball',
              title: 'Train with purpose',
              body: 'Development for athletes at every stage.',
            },
            seo: { title: 'J Starz Training', description: 'Basketball training in Halifax.' },
          },
        }),
      ),
    );

    renderPortal(['/']);

    expect(await screen.findByRole('heading', { name: 'Train with purpose' })).toBeInTheDocument();
    await waitFor(() => expect(document.title).toBe('J Starz Training'));
    expect(document.querySelector('meta[name="description"]')).toHaveAttribute(
      'content',
      'Basketball training in Halifax.',
    );
  });

  it('exposes public navigation for anonymous visitors', async () => {
    renderPortal(['/']);
    expect(await screen.findByRole('heading', { name: 'Develop your game.' })).toBeInTheDocument();
    expect(screen.getAllByRole('link', { name: 'Programs' }).length).toBeGreaterThan(0);
    expect(screen.getAllByRole('link', { name: 'Packages' }).length).toBeGreaterThan(0);
    expect(screen.getAllByRole('link', { name: 'Shop' }).length).toBeGreaterThan(0);
  });

  it('redirects unauthenticated users from protected routes to login', async () => {
    renderPortal(['/account']);
    expect(await screen.findByRole('heading', { name: 'Sign in' })).toBeInTheDocument();
  });

  it('uses a focus-trapped mobile navigation drawer and restores the menu button', async () => {
    renderPortal(['/']);
    await screen.findByRole('heading', { name: 'Develop your game.' });

    const opener = screen.getByRole('button', { name: 'Menu' });
    await userEvent.click(opener);
    expect(screen.getByRole('dialog', { name: 'Menu' })).toBeInTheDocument();

    await userEvent.keyboard('{Escape}');
    expect(screen.queryByRole('dialog', { name: 'Menu' })).not.toBeInTheDocument();
    expect(opener).toHaveFocus();
  });
});
