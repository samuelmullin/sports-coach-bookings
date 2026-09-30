import { forwardRef, type InputHTMLAttributes } from 'react';
import { cn } from '../lib/cn';
import { useFormField } from './FormField';

export interface InputProps extends InputHTMLAttributes<HTMLInputElement> {
  invalid?: boolean;
}

export const Input = forwardRef<HTMLInputElement, InputProps>(
  ({ className, id, invalid, 'aria-describedby': ariaDescribedBy, ...props }, ref) => {
    const field = useFormField();
    const describedBy =
      ariaDescribedBy ??
      (field
        ? [field.helpId, field.hasError ? field.errorId : null].filter(Boolean).join(' ')
        : undefined);
    const isInvalid = invalid ?? field?.hasError ?? false;

    return (
      <input
        ref={ref}
        id={id ?? field?.id}
        aria-invalid={isInvalid || undefined}
        aria-describedby={describedBy || undefined}
        className={cn(
          'flex h-10 w-full rounded-md border border-border bg-surface px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:cursor-not-allowed disabled:opacity-50',
          isInvalid && 'border-danger focus-visible:ring-danger',
          className,
        )}
        {...props}
      />
    );
  },
);
Input.displayName = 'Input';
