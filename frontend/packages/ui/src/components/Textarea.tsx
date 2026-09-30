import { forwardRef, type TextareaHTMLAttributes } from 'react';
import { cn } from '../lib/cn';
import { useFormField } from './FormField';

export interface TextareaProps extends TextareaHTMLAttributes<HTMLTextAreaElement> {
  invalid?: boolean;
}

export const Textarea = forwardRef<HTMLTextAreaElement, TextareaProps>(
  ({ className, id, invalid, 'aria-describedby': ariaDescribedBy, ...props }, ref) => {
    const field = useFormField();
    const describedBy =
      ariaDescribedBy ??
      (field
        ? [field.helpId, field.hasError ? field.errorId : null].filter(Boolean).join(' ')
        : undefined);
    const isInvalid = invalid ?? field?.hasError ?? false;

    return (
      <textarea
        ref={ref}
        id={id ?? field?.id}
        aria-invalid={isInvalid || undefined}
        aria-describedby={describedBy || undefined}
        className={cn(
          'flex min-h-[80px] w-full rounded-md border border-border bg-surface px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:cursor-not-allowed disabled:opacity-50',
          isInvalid && 'border-danger focus-visible:ring-danger',
          className,
        )}
        {...props}
      />
    );
  },
);
Textarea.displayName = 'Textarea';
