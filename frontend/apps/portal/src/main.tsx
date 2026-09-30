import './styles.css';
import './i18n';
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { QueryClientProvider } from '@tanstack/react-query';
import { BrowserRouter } from 'react-router-dom';
import { createQueryClient } from '@scb/api-client';
import { ToastProvider } from '@scb/ui';
import { AppRoutes } from './App';
import { CustomerAuthProvider } from './auth/customer-auth';
import { ReservationProvider } from './features/reservations/ReservationProvider';
import { BrandingProvider } from './theme/branding';
import { setupApiClient } from './api/client';
import { enableMocks, mocksEnabled } from './mocks';

async function bootstrap(): Promise<void> {
  setupApiClient();
  if (mocksEnabled()) {
    await enableMocks();
  }

  const queryClient = createQueryClient();
  const rootElement = document.getElementById('root');
  if (!rootElement) throw new Error('Root element #root not found');

  createRoot(rootElement).render(
    <StrictMode>
      <QueryClientProvider client={queryClient}>
        <ToastProvider>
          <ReservationProvider>
            <BrandingProvider>
              <CustomerAuthProvider>
                <BrowserRouter>
                  <AppRoutes />
                </BrowserRouter>
              </CustomerAuthProvider>
            </BrandingProvider>
          </ReservationProvider>
        </ToastProvider>
      </QueryClientProvider>
    </StrictMode>,
  );
}

void bootstrap();
