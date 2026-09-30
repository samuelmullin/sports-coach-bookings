import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { useState } from 'react';
import { describe, expect, it } from 'vitest';
import { Combobox, type ComboboxOption } from '../Combobox';

const options: ComboboxOption[] = [
  { value: 'u10', label: 'U10' },
  { value: 'u12', label: 'U12' },
  { value: 'u14', label: 'U14' },
];

function Harness() {
  const [value, setValue] = useState<string | undefined>();
  return (
    <Combobox options={options} value={value} onChange={setValue} placeholder="Pick age group" />
  );
}

describe('Combobox', () => {
  it('filters options and selects a value', async () => {
    render(<Harness />);
    await userEvent.click(screen.getByRole('combobox'));
    await userEvent.type(screen.getByPlaceholderText('Search…'), 'u1');
    expect(screen.getByRole('listbox')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('option', { name: 'U12' }));
    expect(screen.getByRole('combobox')).toHaveTextContent('U12');
  });

  it('shows an empty message when nothing matches', async () => {
    render(<Harness />);
    await userEvent.click(screen.getByRole('combobox'));
    await userEvent.type(screen.getByPlaceholderText('Search…'), 'zzz');
    expect(screen.getByText('No results')).toBeInTheDocument();
  });
});
