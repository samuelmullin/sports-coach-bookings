import { QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { HttpResponse, http } from 'msw';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { createQueryClient } from '@scb/api-client';
import { mockBrandings, resetMockSessions, setMockCustomerSession } from '@scb/mocks';
import { server } from '@scb/mocks/server';
import '../../../i18n';
import { AppRoutes } from '../../../App';
import { CustomerAuthProvider } from '../../../auth/customer-auth';
import { BrandingProvider } from '../../../theme/branding';
import { addGuestLine, clearGuestCart, guestLineId } from '../guest-cart';

function renderPortal() {
  const queryClient = createQueryClient();
  return render(
    <QueryClientProvider client={queryClient}>
      <BrandingProvider>
        <CustomerAuthProvider>
          <MemoryRouter initialEntries={['/']}>
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
  clearGuestCart();
  server.use(http.get('/api/portal/branding', () => HttpResponse.json(mockBrandings.demo)));
});

describe('cart icon', () => {
  it('shows a cart icon with no badge when the cart is empty', async () => {
    renderPortal();

    const icon = await screen.findByTestId('cart-icon');
    expect(icon).toBeInTheDocument();
    expect(screen.queryByTestId('cart-count')).not.toBeInTheDocument();
  });

  it('counts a bundle (single package) as one item', async () => {
    addGuestLine({
      id: guestLineId('package', 'pkg-1'),
      type: 'package',
      ref_id: 'pkg-1',
      quantity: 1,
      snapshot: { title: '5-Session Pack', priceMinor: 10000, currency: 'CAD' },
    });

    renderPortal();

    await waitFor(() => expect(screen.getByTestId('cart-count')).toHaveTextContent('1'));
  });

  it('sums quantities across lines (merch quantity counts)', async () => {
    addGuestLine({
      id: guestLineId('package', 'pkg-1'),
      type: 'package',
      ref_id: 'pkg-1',
      quantity: 1,
      snapshot: { title: '5-Session Pack', priceMinor: 10000, currency: 'CAD' },
    });
    addGuestLine({
      id: guestLineId('product', 'var-1'),
      type: 'product',
      ref_id: 'var-1',
      quantity: 2,
      snapshot: { title: 'Home Jersey', priceMinor: 4500, currency: 'CAD' },
    });

    renderPortal();

    await waitFor(() => expect(screen.getByTestId('cart-count')).toHaveTextContent('3'));
  });
});
