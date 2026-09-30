import { ApiError } from '@scb/api-client';

/**
 * All generated hooks wrap the success body as `{ data, status, headers }`.
 * The orval return type unions success and error responses, so callers pass
 * the expected body type explicitly: `body<Session>(query)`.
 */
export function body<T>(query: unknown): T | undefined {
  return (query as { data?: { data?: T } } | undefined)?.data?.data;
}

/** Paginated list endpoints return `{ data: T[], next_cursor }`. */
export function listItems<T>(query: unknown): T[] {
  return (query as { data?: { data?: { data?: T[] } } } | undefined)?.data?.data?.data ?? [];
}

export function nextCursor(query: unknown): string | undefined {
  return (
    (query as { data?: { data?: { next_cursor?: string | null } } } | undefined)?.data?.data
      ?.next_cursor ?? undefined
  );
}

/** Extract the success body from a mutation result. */
export function responseData<T>(result: unknown): T | undefined {
  return (result as { data?: T } | undefined)?.data;
}

export function errorMessage(error: unknown): string {
  if (error instanceof ApiError) return error.message;
  if (error instanceof Error) return error.message;
  return 'Something went wrong';
}

export function errorCode(error: unknown): string | undefined {
  return error instanceof ApiError ? error.code : undefined;
}
