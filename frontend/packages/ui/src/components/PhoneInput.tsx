import { forwardRef } from 'react';
import { cn } from '../lib/cn';
import {
  defaultPhoneCountry,
  findPhoneCountry,
  phoneCountries,
  phoneFlag,
  type PhoneValue,
} from '../lib/phone';
import { useFormField } from './FormField';

export interface PhoneInputProps {
  value?: PhoneValue;
  onChange?: (value: PhoneValue) => void;
  onBlur?: () => void;
  disabled?: boolean;
  invalid?: boolean;
  id?: string;
  name?: string;
  defaultCountry?: string;
  className?: string;
  'aria-describedby'?: string;
}

const selectClassName =
  'h-10 shrink-0 rounded-md border border-border bg-surface px-2 text-sm text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:cursor-not-allowed disabled:opacity-50';

export const PhoneInput = forwardRef<HTMLInputElement, PhoneInputProps>(
  (
    {
      value,
      onChange,
      onBlur,
      disabled,
      invalid,
      id,
      name,
      defaultCountry = defaultPhoneCountry,
      className,
      ...aria
    },
    ref,
  ) => {
    const field = useFormField();
    const current = value ?? { country: defaultCountry, national: '' };
    const region = findPhoneCountry(current.country);
    const isInvalid = invalid ?? field?.hasError ?? false;
    const describedBy =
      aria['aria-describedby'] ??
      (field
        ? [field.helpId, field.hasError ? field.errorId : null].filter(Boolean).join(' ')
        : undefined);

    const emit = (next: Partial<PhoneValue>) => {
      onChange?.({ ...current, ...next });
    };

    return (
      <div className={cn('flex gap-2', className)}>
        <select
          aria-label="Country calling code"
          className={cn(selectClassName, isInvalid && 'border-danger')}
          value={region.iso2}
          disabled={disabled}
          onChange={(event) => emit({ country: event.target.value })}
        >
          {phoneCountries.map((country) => (
            <option key={country.iso2} value={country.iso2}>
              {phoneFlag(country.iso2)} {country.name} (+{country.dialCode})
            </option>
          ))}
        </select>
        <input
          ref={ref}
          id={id ?? field?.id}
          name={name}
          type="tel"
          inputMode="tel"
          autoComplete="tel-national"
          disabled={disabled}
          aria-invalid={isInvalid || undefined}
          aria-describedby={describedBy || undefined}
          className={cn(
            'flex h-10 w-full rounded-md border border-border bg-surface px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:cursor-not-allowed disabled:opacity-50',
            isInvalid && 'border-danger focus-visible:ring-danger',
          )}
          value={current.national}
          onChange={(event) => emit({ national: event.target.value })}
          onBlur={onBlur}
        />
      </div>
    );
  },
);
PhoneInput.displayName = 'PhoneInput';
