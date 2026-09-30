import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react';
import {
  getSportsCoachBookingsWebPortalAccountAccountControllerShowQueryKey,
  useSportsCoachBookingsWebPortalAccountAccountControllerShow,
  useSportsCoachBookingsWebPortalAccountSessionControllerDelete,
  type SportsCoachBookingsWebPortalAccountAccountControllerShow200,
  type SportsCoachBookingsWebPortalAccountAccountControllerShow200CustomerUser,
} from '@scb/api-client';
import { configureApiClient } from '@scb/api-client';

export interface CustomerAuthValue {
  status: 'loading' | 'authenticated' | 'anonymous';
  customerUser?: SportsCoachBookingsWebPortalAccountAccountControllerShow200CustomerUser;
  forbidden: boolean;
  clearForbidden: () => void;
  refresh: () => void;
  signOut: () => Promise<void>;
}

const CustomerAuthContext = createContext<CustomerAuthValue | null>(null);

export function CustomerAuthProvider({ children }: { children: ReactNode }) {
  const [forbidden, setForbidden] = useState(false);

  const accountQuery = useSportsCoachBookingsWebPortalAccountAccountControllerShow({
    query: {
      queryKey: getSportsCoachBookingsWebPortalAccountAccountControllerShowQueryKey(),
      retry: false,
      staleTime: 60_000,
    },
  });

  const signOutMutation = useSportsCoachBookingsWebPortalAccountSessionControllerDelete();

  useEffect(() => {
    configureApiClient({ onForbidden: () => setForbidden(true) });
  }, []);

  const account = accountQuery.data?.data as
    SportsCoachBookingsWebPortalAccountAccountControllerShow200 | undefined;
  const customerUser = account?.customer_user;

  const status: CustomerAuthValue['status'] = accountQuery.isLoading
    ? 'loading'
    : customerUser
      ? 'authenticated'
      : 'anonymous';

  const signOut = useCallback(async () => {
    try {
      await signOutMutation.mutateAsync();
    } finally {
      window.location.assign('/login');
    }
  }, [signOutMutation]);

  const value: CustomerAuthValue = {
    status,
    customerUser,
    forbidden,
    clearForbidden: () => setForbidden(false),
    refresh: () => {
      void accountQuery.refetch();
    },
    signOut,
  };

  return <CustomerAuthContext.Provider value={value}>{children}</CustomerAuthContext.Provider>;
}

export function useCustomerAuth(): CustomerAuthValue {
  const context = useContext(CustomerAuthContext);
  if (!context) {
    throw new Error('useCustomerAuth must be used within <CustomerAuthProvider>');
  }
  return context;
}

/** Like `useCustomerAuth` but returns `null` outside a provider (e.g. tests or
 * public pages that render a component which can also appear signed in). */
export function useOptionalCustomerAuth(): CustomerAuthValue | null {
  return useContext(CustomerAuthContext);
}
