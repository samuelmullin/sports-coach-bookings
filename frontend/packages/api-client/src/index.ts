export * from './generated/endpoints';
export * from './generated/model';

export {
  ApiError,
  configureApiClient,
  customFetch,
  getApiClientConfig,
  toApiError,
  unwrap,
} from './mutator/custom-fetch';
export type {
  ApiClientConfig,
  ApiErrorBody,
  ApiErrorInit,
  ApiFieldErrors,
  FetchResult,
} from './mutator/custom-fetch';

export { createQueryClient, defaultQueryClientConfig } from './query-client';
export { applyApiFieldErrors } from './form';
export type { AppliedApiError, ApplyApiFieldErrorsOptions } from './form';
