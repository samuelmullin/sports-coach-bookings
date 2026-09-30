import { QueryClient, type QueryClientConfig } from '@tanstack/react-query';
import { ApiError } from './mutator/custom-fetch';

export const defaultQueryClientConfig: QueryClientConfig = {
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      gcTime: 5 * 60_000,
      refetchOnWindowFocus: false,
      retry: (failureCount, error) => {
        if (error instanceof ApiError && error.status < 500) return false;
        return failureCount < 2;
      },
    },
    mutations: {
      retry: false,
    },
  },
};

export function createQueryClient(
  config: QueryClientConfig = defaultQueryClientConfig,
): QueryClient {
  return new QueryClient(config);
}
