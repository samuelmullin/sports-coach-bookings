import * as SwitchPrimitive from '@radix-ui/react-switch';
import { forwardRef, useId, type ComponentPropsWithoutRef } from 'react';
import { cn } from '../lib/cn';

export interface SwitchProps extends Omit<
  ComponentPropsWithoutRef<typeof SwitchPrimitive.Root>,
  'id'
> {
  id?: string;
  label?: string;
}

export const Switch = forwardRef<React.ElementRef<typeof SwitchPrimitive.Root>, SwitchProps>(
  ({ className, id, label, ...props }, ref) => {
    const generatedId = useId();
    const switchId = id ?? generatedId;
    const control = (
      <SwitchPrimitive.Root
        ref={ref}
        id={switchId}
        className={cn(
          'peer inline-flex h-6 w-11 shrink-0 cursor-pointer items-center rounded-full border-2 border-transparent transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:cursor-not-allowed disabled:opacity-50 data-[state=checked]:bg-primary data-[state=unchecked]:bg-muted',
          className,
        )}
        {...props}
      >
        <SwitchPrimitive.Thumb className="pointer-events-none block h-5 w-5 rounded-full bg-surface shadow-lg ring-0 transition-transform data-[state=checked]:translate-x-5 data-[state=unchecked]:translate-x-0" />
      </SwitchPrimitive.Root>
    );

    if (!label) return control;

    return (
      <div className="flex items-center gap-2">
        {control}
        <label htmlFor={switchId} className="text-sm text-foreground">
          {label}
        </label>
      </div>
    );
  },
);
Switch.displayName = 'Switch';
