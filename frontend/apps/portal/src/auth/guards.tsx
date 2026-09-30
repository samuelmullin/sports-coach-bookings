import type { ReactNode } from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { Splash } from '@scb/ui';
import { useCustomerAuth } from './customer-auth';

export function RequireCustomerAuth({ children }: { children: ReactNode }) {
  const { status } = useCustomerAuth();
  const location = useLocation();

  if (status === 'loading') {
    return <Splash label="Loading portal…" />;
  }
  if (status === 'anonymous') {
    return <Navigate to="/login" state={{ from: location.pathname }} replace />;
  }
  return <>{children}</>;
}

export function RequireAnonymous({ children }: { children: ReactNode }) {
  const { status } = useCustomerAuth();
  if (status === 'loading') return <Splash label="Loading portal…" />;
  if (status === 'authenticated') return <Navigate to="/account" replace />;
  return <>{children}</>;
}
