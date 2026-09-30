import { forwardRef, useEffect, useState, type InputHTMLAttributes } from 'react';
import { cn } from '../lib/cn';
import { formatMoney, minorUnitExponent, parseMoneyToMinor } from '../format/money';
import { useFormField } from './FormField';

function displayFromValue(value: number | null | undefined, exponent: number): string {
  return value == null ? '' : (value / 10 ** exponent).toFixed(exponent);
}

export interface MoneyDisplayProps {
  amountMinor: number;
  currency: string;
  locale?: string;
  className?: string;
}

export function MoneyDisplay({ amountMinor, currency, locale, className }: MoneyDisplayProps) {
  return (
    <span className={className} data-currency={currency}>
      {formatMoney(amountMinor, currency, { locale })}
    </span>
  );
}

export interface MoneyInputProps extends Omit<
  InputHTMLAttributes<HTMLInputElement>,
  'value' | 'onChange' | 'type'
> {
  value?: number | null;
  onChange?: (minor: number | null) => void;
  currency: string;
  locale?: string;
  invalid?: boolean;
}

export const MoneyInput = forwardRef<HTMLInputElement, MoneyInputProps>(
  (
    {
      value,
      onChange,
      currency,
      locale = 'en-CA',
      invalid,
      className,
      id,
      placeholder,
      onFocus,
      onBlur,
      ...props
    },
    ref,
  ) => {
    const field = useFormField();
    const exponent = minorUnitExponent(currency);
    const [text, setText] = useState(() => displayFromValue(value, exponent));
    const [focused, setFocused] = useState(false);

    useEffect(() => {
      if (!focused) setText(displayFromValue(value, exponent));
    }, [value, exponent, focused]);

    return (
      <div className="relative">
        <span className="pointer-events-none absolute inset-y-0 left-3 flex items-center text-sm text-muted-foreground">
          {formatMoney(0, currency, {
            locale,
            minimumFractionDigits: 0,
          })
            .replace(/[\d.,\s]/g, '')
            .trim() || currency.toUpperCase()}
        </span>
        <input
          ref={ref}
          id={id ?? field?.id}
          type="text"
          inputMode="decimal"
          value={text}
          placeholder={placeholder ?? `0.${'0'.repeat(exponent)}`}
          aria-invalid={invalid ?? field?.hasError ?? false}
          onFocus={(event) => {
            setFocused(true);
            onFocus?.(event);
          }}
          onBlur={(event) => {
            setFocused(false);
            onBlur?.(event);
          }}
          onChange={(event) => {
            setText(event.target.value);
            onChange?.(parseMoneyToMinor(event.target.value, currency));
          }}
          className={cn(
            'flex h-10 w-full rounded-md border border-border bg-surface py-2 pl-10 pr-3 text-sm text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:cursor-not-allowed disabled:opacity-50',
            (invalid ?? field?.hasError) && 'border-danger',
            className,
          )}
          {...props}
        />
      </div>
    );
  },
);
MoneyInput.displayName = 'MoneyInput';
