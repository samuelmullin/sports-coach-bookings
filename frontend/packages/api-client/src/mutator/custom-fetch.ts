export type ApiFieldErrors = Record<string, string[] | string>;

export interface ApiErrorBody {
  error?: {
    code?: string;
    message?: string;
    details?: unknown;
  };
}

export interface ApiErrorInit {
  code: string;
  message: string;
  status: number;
  fields?: ApiFieldErrors;
  details?: unknown;
  body?: unknown;
}

export class ApiError extends Error {
  readonly code: string;
  readonly status: number;
  readonly fields?: ApiFieldErrors;
  readonly details?: unknown;
  readonly body?: unknown;

  constructor(init: ApiErrorInit) {
    super(init.message);
    this.name = 'ApiError';
    this.code = init.code;
    this.status = init.status;
    this.fields = init.fields;
    this.details = init.details;
    this.body = init.body;
  }

  get isUnauthorized(): boolean {
    return this.status === 401;
  }

  get isForbidden(): boolean {
    return this.status === 403;
  }
}

export interface ApiClientConfig {
  baseUrl: string;
  csrfCookieName: string;
  csrfHeaderName: string;
  getCsrfToken?: () => string | undefined;
  onUnauthorized?: (error: ApiError) => void;
  onForbidden?: (error: ApiError) => void;
}

const defaultConfig: ApiClientConfig = {
  baseUrl: '',
  csrfCookieName: 'csrf_token',
  csrfHeaderName: 'x-csrf-token',
};

let config: ApiClientConfig = { ...defaultConfig };

export function configureApiClient(next: Partial<ApiClientConfig>): void {
  config = { ...config, ...next };
}

export function getApiClientConfig(): ApiClientConfig {
  return config;
}

const MUTATING_METHODS = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

function readCookie(name: string): string | undefined {
  if (typeof document === 'undefined') return undefined;
  const match = document.cookie.split('; ').find((row) => row.startsWith(`${name}=`));
  if (!match) return undefined;
  return decodeURIComponent(match.slice(name.length + 1));
}

function resolveCsrfToken(): string | undefined {
  if (config.getCsrfToken) return config.getCsrfToken();
  const meta =
    typeof document !== 'undefined'
      ? document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
      : null;
  return meta ?? readCookie(config.csrfCookieName);
}

function normalizeFields(details: unknown): ApiFieldErrors | undefined {
  if (!details || typeof details !== 'object') return undefined;
  const record = details as Record<string, unknown>;
  const fields = (record.fields ?? record) as unknown;
  if (!fields || typeof fields !== 'object') return undefined;
  const normalized: ApiFieldErrors = {};
  for (const [key, value] of Object.entries(fields as Record<string, unknown>)) {
    if (typeof value === 'string' || Array.isArray(value)) {
      normalized[key] = value as string[] | string;
    }
  }
  return Object.keys(normalized).length > 0 ? normalized : undefined;
}

export function toApiError(status: number, body: unknown): ApiError {
  const envelope = (body ?? {}) as ApiErrorBody;
  const error = envelope.error ?? {};
  return new ApiError({
    code: error.code ?? `http_${status}`,
    message: error.message ?? `Request failed with status ${status}`,
    status,
    fields: normalizeFields(error.details),
    details: error.details,
    body,
  });
}

export function resolveRequestUrl(url: string): string {
  if (/^https?:\/\//i.test(url) || url.startsWith('//')) return url;
  const base =
    config.baseUrl ||
    (typeof window !== 'undefined' && window.location ? window.location.origin : '');
  if (!base) return url;
  return `${base.replace(/\/$/, '')}/${url.replace(/^\//, '')}`;
}

export interface FetchResult<TData> {
  data: TData;
  status: number;
  headers: Headers;
}

export const customFetch = async <T>(url: string, options: RequestInit = {}): Promise<T> => {
  const method = (options.method ?? 'GET').toUpperCase();
  const headers = new Headers(options.headers);

  if (!headers.has('Accept')) headers.set('Accept', 'application/json');

  if (MUTATING_METHODS.has(method)) {
    const token = resolveCsrfToken();
    if (token && !headers.has(config.csrfHeaderName)) {
      headers.set(config.csrfHeaderName, token);
    }
  }

  const response = await fetch(resolveRequestUrl(url), {
    credentials: 'include',
    ...options,
    method,
    headers,
  });

  const text = [204, 205, 304].includes(response.status) ? '' : await response.text();

  let body: unknown;
  if (text) {
    try {
      body = JSON.parse(text);
    } catch {
      body = text;
    }
  }

  if (!response.ok) {
    const error = toApiError(response.status, body);
    if (error.isUnauthorized) config.onUnauthorized?.(error);
    if (error.isForbidden) config.onForbidden?.(error);
    throw error;
  }

  return {
    data: body as T extends FetchResult<infer TData> ? TData : never,
    status: response.status,
    headers: response.headers,
  } as T;
};

export function unwrap<TData>(result: FetchResult<TData> | undefined): TData | undefined {
  return result?.data;
}

export default customFetch;
