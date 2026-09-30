import { configureApiClient } from '@scb/api-client';

export function setupApiClient(): void {
  configureApiClient({
    baseUrl: import.meta.env.VITE_API_BASE_URL ?? '',
  });
}
