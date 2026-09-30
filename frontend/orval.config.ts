import { defineConfig } from 'orval';

export default defineConfig({
  apiClient: {
    input: {
      target: '../docs/openapi.json',
    },
    output: {
      mode: 'split',
      target: './packages/api-client/src/generated/endpoints.ts',
      schemas: './packages/api-client/src/generated/model',
      client: 'react-query',
      httpClient: 'fetch',
      clean: true,
      prettier: false,
      override: {
        mutator: {
          path: './packages/api-client/src/mutator/custom-fetch.ts',
          name: 'customFetch',
        },
        query: {
          useQuery: true,
          useInfinite: false,
          signal: false,
        },
      },
    },
  },
  apiMocks: {
    input: {
      target: '../docs/openapi.json',
    },
    output: {
      mode: 'split',
      target: './packages/mocks/src/generated/endpoints.ts',
      schemas: './packages/mocks/src/generated/model',
      client: 'react-query',
      httpClient: 'fetch',
      mock: true,
      clean: true,
      prettier: false,
      override: {
        query: {
          useQuery: true,
          useInfinite: false,
          signal: true,
        },
      },
    },
  },
});
