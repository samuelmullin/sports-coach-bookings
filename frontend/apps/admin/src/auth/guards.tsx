import type { ReactNode } from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { Splash } from '@scb/ui';
import { useStaffAuth, type StaffRole } from './staff-auth';
import { ForbiddenPage } from '../pages/ForbiddenPage';

export function RequireStaffAuth({ children }: { children: ReactNode }) {
  const { status } = useStaffAuth();
  const location = useLocation();

  if (status === 'loading') {
    return <Splash label="Loading admin…" />;
  }
  if (status === 'anonymous' || status === 'error') {
    return <Navigate to="/login" state={{ from: location.pathname }} replace />;
  }
  return <>{children}</>;
}

export function RequireRole({ roles, children }: { roles: StaffRole[]; children: ReactNode }) {
  const { role } = useStaffAuth();
  if (role && roles.includes(role)) {
    return <>{children}</>;
  }
  return <ForbiddenPage />;
}

export function RequireAnonymous({ children }: { children: ReactNode }) {
  const { status } = useStaffAuth();
  if (status === 'loading') {
    return <Splash label="Loading admin…" />;
  }
  if (status === 'authenticated') {
    return <Navigate to="/" replace />;
  }
  return <>{children}</>;
}
