import type { ReactElement, ReactNode } from 'react';
import { QueryClientProvider } from '@tanstack/react-query';
import { render } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { ToastProvider } from '@scb/ui';
import { createQueryClient } from '@scb/api-client';
import { CustomerAuthProvider } from '../auth/customer-auth';
import { ReservationProvider } from '../features/reservations/ReservationProvider';
import '../i18n';

export function createTestQueryClient() {
  return createQueryClient({
    defaultOptions: {
      queries: { retry: false, staleTime: 0 },
      mutations: { retry: false },
    },
  });
}

export function renderWithProviders(
  ui: ReactElement,
  { route = '/', withAuth = false }: { route?: string; withAuth?: boolean } = {},
): ReturnType<typeof render> {
  const queryClient = createTestQueryClient();

  function Wrapper({ children }: { children: ReactNode }) {
    const inner = <MemoryRouter initialEntries={[route]}>{children}</MemoryRouter>;
    return (
      <QueryClientProvider client={queryClient}>
        <ToastProvider>
          <ReservationProvider>
            {withAuth ? <CustomerAuthProvider>{inner}</CustomerAuthProvider> : inner}
          </ReservationProvider>
        </ToastProvider>
      </QueryClientProvider>
    );
  }

  return render(ui, { wrapper: Wrapper });
}
