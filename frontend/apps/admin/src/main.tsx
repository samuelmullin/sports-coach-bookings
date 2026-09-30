import './styles.css';
import './i18n';
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { QueryClientProvider } from '@tanstack/react-query';
import { BrowserRouter } from 'react-router-dom';
import { createQueryClient } from '@scb/api-client';
import { ToastProvider } from '@scb/ui';
import { AppRoutes } from './App';
import { StaffAuthProvider } from './auth/staff-auth';
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
          <StaffAuthProvider>
            <BrowserRouter basename="/admin">
              <AppRoutes />
            </BrowserRouter>
          </StaffAuthProvider>
        </ToastProvider>
      </QueryClientProvider>
    </StrictMode>,
  );
}

void bootstrap();
