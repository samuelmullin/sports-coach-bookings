import { QueryClient } from '@tanstack/react-query';
import { describe, expect, it, vi } from 'vitest';
import { createQueryClient } from './query-client';
import { applyApiFieldErrors } from './form';
import { ApiError, customFetch, configureApiClient, toApiError } from './mutator/custom-fetch';

describe('createQueryClient', () => {
  it('creates a query client with sensible defaults', () => {
    const client = createQueryClient();
    expect(client).toBeInstanceOf(QueryClient);
    expect(client.getDefaultOptions().queries?.staleTime).toBe(30_000);
  });
});

describe('applyApiFieldErrors', () => {
  it('maps API field errors onto react-hook-form fields', () => {
    const setError = vi.fn();
    const error = new ApiError({
      code: 'unprocessable_entity',
      message: 'Invalid',
      status: 422,
      fields: { email: ['is invalid'], password: 'is too short' },
    });
    const result = applyApiFieldErrors(error, { setError });
    expect(result.handled).toBe(true);
    expect(setError).toHaveBeenCalledWith('email', {
      type: 'server',
      message: 'is invalid',
    });
    expect(setError).toHaveBeenCalledWith('password', {
      type: 'server',
      message: 'is too short',
    });
  });

  it('honours mapped field names', () => {
    const setError = vi.fn();
    const error = new ApiError({
      code: 'unprocessable_entity',
      message: 'Invalid',
      status: 422,
      fields: { email_address: ['bad'] },
    });
    applyApiFieldErrors(error, {
      setError,
      mappedFields: { email_address: 'email' },
    });
    expect(setError).toHaveBeenCalledWith('email', {
      type: 'server',
      message: 'bad',
    });
  });

  it('falls back to a form-level error for non-field failures', () => {
    const setError = vi.fn();
    applyApiFieldErrors(new Error('boom'), {
      setError,
      fallbackField: 'root',
    });
    expect(setError).toHaveBeenCalledWith('root', {
      type: 'server',
      message: 'boom',
    });
  });
});

describe('toApiError', () => {
  it('parses the standard error envelope', () => {
    const error = toApiError(422, {
      error: {
        code: 'unprocessable_entity',
        message: 'Invalid',
        details: { fields: { email: ['taken'] } },
      },
    });
    expect(error.code).toBe('unprocessable_entity');
    expect(error.fields).toEqual({ email: ['taken'] });
  });
});

describe('customFetch', () => {
  it('sends credentials, parses JSON, and returns the orval envelope', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      }),
    );

    const result = await customFetch<{ data: { ok: boolean }; status: number }>(
      '/api/portal/branding',
    );
    expect(result.data).toEqual({ ok: true });
    expect(result.status).toBe(200);
    const [, init] = fetchMock.mock.calls[0];
    expect(init?.credentials).toBe('include');
    fetchMock.mockRestore();
  });

  it('throws ApiError with fields on a 422', async () => {
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(
        JSON.stringify({
          error: {
            code: 'unprocessable_entity',
            message: 'Invalid',
            details: { fields: { slug: ['is taken'] } },
          },
        }),
        { status: 422, headers: { 'Content-Type': 'application/json' } },
      ),
    );

    await expect(customFetch('/api/platform/signup')).rejects.toMatchObject({
      status: 422,
      code: 'unprocessable_entity',
      fields: { slug: ['is taken'] },
    });
    fetchMock.mockRestore();
  });

  it('invokes handlers for 401 and 403', async () => {
    const onUnauthorized = vi.fn();
    const onForbidden = vi.fn();
    configureApiClient({ onUnauthorized, onForbidden });
    const fetchMock = vi.spyOn(globalThis, 'fetch').mockResolvedValue(
      new Response(JSON.stringify({ error: { code: 'forbidden', message: 'no', details: {} } }), {
        status: 403,
        headers: { 'Content-Type': 'application/json' },
      }),
    );
    await expect(customFetch('/api/staff/players')).rejects.toBeInstanceOf(ApiError);
    expect(onForbidden).toHaveBeenCalled();
    fetchMock.mockRestore();
    configureApiClient({ onUnauthorized: undefined, onForbidden: undefined, baseUrl: '' });
  });
});
