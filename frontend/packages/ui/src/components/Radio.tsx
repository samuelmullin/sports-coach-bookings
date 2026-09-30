import * as RadioGroupPrimitive from '@radix-ui/react-radio-group';
import { forwardRef, useId, type ComponentPropsWithoutRef } from 'react';
import { cn } from '../lib/cn';

export interface RadioOption {
  value: string;
  label: string;
  disabled?: boolean;
}

export interface RadioGroupProps extends Omit<
  ComponentPropsWithoutRef<typeof RadioGroupPrimitive.Root>,
  'children'
> {
  options: RadioOption[];
  label?: string;
}

export const RadioGroup = forwardRef<
  React.ElementRef<typeof RadioGroupPrimitive.Root>,
  RadioGroupProps
>(({ className, options, label, ...props }, ref) => {
  const groupId = useId();
  return (
    <RadioGroupPrimitive.Root
      ref={ref}
      aria-label={label}
      className={cn('flex flex-col gap-2', className)}
      {...props}
    >
      {options.map((option) => {
        const optionId = `${groupId}-${option.value}`;
        return (
          <div key={option.value} className="flex items-center gap-2">
            <RadioGroupPrimitive.Item
              id={optionId}
              value={option.value}
              disabled={option.disabled}
              className="h-5 w-5 shrink-0 rounded-full border border-border bg-surface focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:cursor-not-allowed disabled:opacity-50 data-[state=checked]:border-primary"
            >
              <RadioGroupPrimitive.Indicator className="flex h-full w-full items-center justify-center">
                <span className="h-2.5 w-2.5 rounded-full bg-primary" />
              </RadioGroupPrimitive.Indicator>
            </RadioGroupPrimitive.Item>
            <label htmlFor={optionId} className="text-sm text-foreground">
              {option.label}
            </label>
          </div>
        );
      })}
    </RadioGroupPrimitive.Root>
  );
});
RadioGroup.displayName = 'RadioGroup';

export const Radio = RadioGroupPrimitive.Item;
