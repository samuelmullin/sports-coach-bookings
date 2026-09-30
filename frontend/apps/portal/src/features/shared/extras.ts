/**
 * Endpoints that are **not in the OpenAPI spec**.
 *
 * The portal does not expose the tenant currency/timezone. Feature code still
 * needs both (money is stored in minor units and all times render in the venue
 * timezone), so we read them from `/api/portal/context`, served by MSW in the
 * browser and in tests. Fallback defaults keep the UI usable against the live
 * API until the endpoint lands. Replace with a generated hook when the backend
 * exposes it.
 */
import { useQuery } from '@tanstack/react-query';
import { customFetch, type FetchResult } from '@scb/api-client';

async function fetchBody<T>(url: string, init?: RequestInit): Promise<T> {
  const result = await customFetch<FetchResult<T>>(url, init);
  return result.data;
}

export interface PortalSettings {
  currency: string;
  timezone: string;
}

export const PORTAL_SETTINGS_KEY = ['/api/portal/context'];

export const DEFAULT_PORTAL_SETTINGS: PortalSettings = {
  currency: 'CAD',
  timezone: 'America/Toronto',
};

export function usePortalSettings(): PortalSettings {
  const query = useQuery({
    queryKey: PORTAL_SETTINGS_KEY,
    queryFn: () => fetchBody<PortalSettings>('/api/portal/context'),
    retry: false,
    staleTime: Infinity,
  });
  return {
    currency: query.data?.currency ?? DEFAULT_PORTAL_SETTINGS.currency,
    timezone: query.data?.timezone ?? DEFAULT_PORTAL_SETTINGS.timezone,
  };
}

export { fetchBody };
