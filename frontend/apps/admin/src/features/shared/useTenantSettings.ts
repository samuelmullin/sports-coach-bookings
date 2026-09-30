import { useSettings } from '../../api/endpoints';
import { body } from './api-utils';
import type { TenantSettings } from '../../api/endpoints';

const FALLBACK_TIMEZONE = 'America/Toronto';
const FALLBACK_CURRENCY = 'CAD';

export interface TenantContext {
  settings?: TenantSettings;
  timezone: string;
  currency: string;
  loading: boolean;
}

export function useTenantSettings(): TenantContext {
  const query = useSettings();
  const settings = body<TenantSettings>(query);
  return {
    settings,
    timezone: settings?.tenant?.timezone ?? FALLBACK_TIMEZONE,
    currency: settings?.tenant?.currency ?? FALLBACK_CURRENCY,
    loading: query.isLoading,
  };
}
