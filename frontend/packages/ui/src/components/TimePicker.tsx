import { forwardRef, type InputHTMLAttributes } from 'react';
import { cn } from '../lib/cn';
import { useFormField } from './FormField';

export interface TimePickerProps extends Omit<InputHTMLAttributes<HTMLInputElement>, 'type'> {
  invalid?: boolean;
  minuteStep?: number;
}

export const TimePicker = forwardRef<HTMLInputElement, TimePickerProps>(
  ({ className, id, invalid, minuteStep = 15, step, ...props }, ref) => {
    const field = useFormField();
    const isInvalid = invalid ?? field?.hasError ?? false;
    const seconds = (step ?? minuteStep * 60) as number;

    return (
      <input
        ref={ref}
        type="time"
        id={id ?? field?.id}
        step={seconds}
        aria-invalid={isInvalid || undefined}
        className={cn(
          'flex h-10 w-full rounded-md border border-border bg-surface px-3 py-2 text-sm text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:cursor-not-allowed disabled:opacity-50',
          isInvalid && 'border-danger',
          className,
        )}
        {...props}
      />
    );
  },
);
TimePicker.displayName = 'TimePicker';
