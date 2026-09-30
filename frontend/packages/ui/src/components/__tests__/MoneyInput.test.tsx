import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { useState } from 'react';
import { describe, expect, it, vi } from 'vitest';
import { MoneyDisplay, MoneyInput } from '../MoneyInput';

function MoneyHarness({
  initial = 1250,
  onChange,
}: {
  initial?: number | null;
  onChange?: (value: number | null) => void;
}) {
  const [value, setValue] = useState<number | null>(initial);
  return (
    <MoneyInput
      value={value}
      currency="CAD"
      aria-label="Amount"
      onChange={(next) => {
        setValue(next);
        onChange?.(next);
      }}
    />
  );
}

describe('MoneyDisplay', () => {
  it('formats minor units in the tenant currency', () => {
    render(<MoneyDisplay amountMinor={1250} currency="CAD" />);
    expect(screen.getByText('$12.50')).toBeInTheDocument();
  });

  it('handles currencies without minor units', () => {
    render(<MoneyDisplay amountMinor={500} currency="JPY" />);
    const display = screen.getByText(/500/);
    expect(display).toBeInTheDocument();
    expect(display.textContent).not.toContain('.');
  });
});

describe('MoneyInput', () => {
  it('shows the value in major units and emits minor units', async () => {
    const onChange = vi.fn();
    render(<MoneyHarness onChange={onChange} />);
    const input = screen.getByLabelText('Amount');
    expect(input).toHaveValue('12.50');
    await userEvent.clear(input);
    await userEvent.type(input, '9.99');
    expect(onChange).toHaveBeenLastCalledWith(999);
  });

  it('emits null for empty input', async () => {
    const onChange = vi.fn();
    render(<MoneyHarness initial={100} onChange={onChange} />);
    await userEvent.clear(screen.getByLabelText('Amount'));
    expect(onChange).toHaveBeenLastCalledWith(null);
  });
});
