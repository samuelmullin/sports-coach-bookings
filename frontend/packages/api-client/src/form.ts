import type { FieldValues, Path, UseFormSetError } from 'react-hook-form';
import { ApiError } from './mutator/custom-fetch';

export interface ApplyApiFieldErrorsOptions<TFieldValues extends FieldValues> {
  setError: UseFormSetError<TFieldValues>;
  mappedFields?: Record<string, Path<TFieldValues>>;
  fallbackField?: Path<TFieldValues>;
}

export interface AppliedApiError {
  handled: boolean;
  message: string;
  fieldErrors: Record<string, string>;
}

export function applyApiFieldErrors<TFieldValues extends FieldValues>(
  error: unknown,
  options: ApplyApiFieldErrorsOptions<TFieldValues>,
): AppliedApiError {
  const { setError, mappedFields = {}, fallbackField } = options;

  if (!(error instanceof ApiError) || !error.fields) {
    const message = error instanceof Error ? error.message : 'Something went wrong';
    if (fallbackField) {
      setError(fallbackField, { type: 'server', message });
    }
    return { handled: false, message, fieldErrors: {} };
  }

  const fieldErrors: Record<string, string> = {};
  let handled = false;

  for (const [field, value] of Object.entries(error.fields)) {
    const message = Array.isArray(value) ? value.join(', ') : value;
    fieldErrors[field] = message;
    const target = mappedFields[field] ?? (field as Path<TFieldValues>);
    try {
      setError(target, { type: 'server', message });
      handled = true;
    } catch {
      // ignore unknown field names
    }
  }

  if (!handled && fallbackField) {
    setError(fallbackField, {
      type: 'server',
      message: error.message,
    });
  }

  return { handled, message: error.message, fieldErrors };
}
