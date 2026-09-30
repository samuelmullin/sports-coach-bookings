import { createContext, useContext, useId, type HTMLAttributes, type ReactNode } from 'react';
import { cn } from '../lib/cn';

interface FormFieldContextValue {
  id: string;
  errorId: string;
  helpId: string;
  hasError: boolean;
  required: boolean;
}

const FormFieldContext = createContext<FormFieldContextValue | null>(null);

export function useFormField(): FormFieldContextValue | null {
  return useContext(FormFieldContext);
}

export interface FormFieldProps extends HTMLAttributes<HTMLDivElement> {
  label?: ReactNode;
  help?: ReactNode;
  error?: ReactNode;
  required?: boolean;
  id?: string;
  children: ReactNode;
}

export function FormField({
  label,
  help,
  error,
  required = false,
  id,
  children,
  className,
  ...props
}: FormFieldProps) {
  const generatedId = useId();
  const fieldId = id ?? generatedId;
  const errorId = `${fieldId}-error`;
  const helpId = `${fieldId}-help`;
  const hasError = Boolean(error);

  const ctx: FormFieldContextValue = {
    id: fieldId,
    errorId,
    helpId,
    hasError,
    required,
  };

  return (
    <FormFieldContext.Provider value={ctx}>
      <div className={cn('flex flex-col gap-1.5', className)} {...props}>
        {label ? (
          <label htmlFor={fieldId} className="text-sm font-medium text-foreground">
            {label}
            {required ? (
              <span aria-hidden="true" className="ml-0.5 text-danger">
                *
              </span>
            ) : null}
          </label>
        ) : null}
        {children}
        {help && !hasError ? (
          <p id={helpId} className="text-xs text-muted-foreground">
            {help}
          </p>
        ) : null}
        {hasError ? (
          <p id={errorId} role="alert" className="text-xs font-medium text-danger">
            {error}
          </p>
        ) : null}
      </div>
    </FormFieldContext.Provider>
  );
}
