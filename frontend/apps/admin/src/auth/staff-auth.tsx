import { createContext, useCallback, useContext, useEffect, useMemo, type ReactNode } from 'react';
import {
  ApiError,
  configureApiClient,
  getSportsCoachBookingsWebPlatformMeControllerShowQueryKey,
  useSportsCoachBookingsWebPlatformMeControllerShow,
  useSportsCoachBookingsWebPlatformSessionControllerDelete,
  type SportsCoachBookingsWebPlatformMeControllerShow200,
  type SportsCoachBookingsWebPlatformMeControllerShow200MembershipsItem,
  type SportsCoachBookingsWebPlatformMeControllerShow200MembershipsItemRole,
  type SportsCoachBookingsWebPlatformMeControllerShow200StaffUser,
} from '@scb/api-client';

export type StaffRole = SportsCoachBookingsWebPlatformMeControllerShow200MembershipsItemRole;
export type StaffMembership = SportsCoachBookingsWebPlatformMeControllerShow200MembershipsItem;

export interface StaffAuthValue {
  status: 'loading' | 'authenticated' | 'anonymous' | 'error';
  staffUser?: SportsCoachBookingsWebPlatformMeControllerShow200StaffUser;
  memberships: StaffMembership[];
  membership?: StaffMembership;
  role?: StaffRole;
  forbidden: boolean;
  clearForbidden: () => void;
  refresh: () => void;
  signOut: () => Promise<void>;
  tenantSlug?: string;
  buildTenantUrl: (slug: string) => string;
}

const StaffAuthContext = createContext<StaffAuthValue | null>(null);

export function currentHostSlug(): string | undefined {
  if (typeof window === 'undefined') return undefined;
  const { hostname } = window.location;
  if (/^(localhost|\d+\.\d+\.\d+\.\d+)$/.test(hostname)) return undefined;
  return hostname.split('.')[0];
}

export function buildTenantUrl(slug: string): string {
  if (typeof window === 'undefined') return `https://${slug}.sportscoachbookings.com/admin`;
  const url = new URL(window.location.href);
  const parts = url.hostname.split('.');
  if (/^(localhost|\d+\.\d+\.\d+\.\d+)$/.test(url.hostname)) {
    url.searchParams.set('tenant', slug);
  } else {
    url.hostname = [slug, ...parts.slice(1)].join('.');
  }
  return url.toString();
}

export function StaffAuthProvider({ children }: { children: ReactNode }) {
  const meQuery = useSportsCoachBookingsWebPlatformMeControllerShow({
    query: {
      queryKey: getSportsCoachBookingsWebPlatformMeControllerShowQueryKey(),
      retry: false,
      staleTime: 60_000,
    },
  });

  const me = meQuery.data?.data as SportsCoachBookingsWebPlatformMeControllerShow200 | undefined;

  const signOutMutation = useSportsCoachBookingsWebPlatformSessionControllerDelete();

  useEffect(() => {
    // 403s are handled where they happen (role guards and per-screen
    // "not on your roster" states) rather than blanking the whole shell, so
    // the global forbidden boundary stays opt-in and unused by default.
    configureApiClient({
      onUnauthorized: () => undefined,
      onForbidden: () => undefined,
    });
  }, []);

  const memberships = useMemo(() => me?.memberships ?? [], [me]);

  const hostSlug = currentHostSlug();
  const membership = useMemo(() => {
    if (memberships.length === 0) return undefined;
    return memberships.find((item) => item.tenant?.slug === hostSlug) ?? memberships[0];
  }, [memberships, hostSlug]);

  const status: StaffAuthValue['status'] = meQuery.isLoading
    ? 'loading'
    : me
      ? 'authenticated'
      : 'anonymous';

  const signOut = useCallback(async () => {
    try {
      await signOutMutation.mutateAsync();
    } finally {
      window.location.assign('/admin/login');
    }
  }, [signOutMutation]);

  const refresh = useCallback(() => {
    void meQuery.refetch();
  }, [meQuery]);

  const value: StaffAuthValue = {
    status,
    staffUser: me?.staff_user,
    memberships,
    membership,
    role: membership?.role,
    forbidden: false,
    clearForbidden: () => undefined,
    refresh,
    signOut,
    tenantSlug: membership?.tenant?.slug,
    buildTenantUrl,
  };

  return <StaffAuthContext.Provider value={value}>{children}</StaffAuthContext.Provider>;
}

export function useStaffAuth(): StaffAuthValue {
  const context = useContext(StaffAuthContext);
  if (!context) {
    throw new Error('useStaffAuth must be used within <StaffAuthProvider>');
  }
  return context;
}

export function isApiError(error: unknown): error is ApiError {
  return error instanceof ApiError;
}
