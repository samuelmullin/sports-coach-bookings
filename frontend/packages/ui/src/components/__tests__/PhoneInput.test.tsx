import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { useState } from 'react';
import { describe, expect, it, vi } from 'vitest';
import { FormField } from '../FormField';
import { PhoneInput } from '../PhoneInput';
import { composeE164, type PhoneValue } from '../../lib/phone';

function Harness({ onChange }: { onChange?: (value: PhoneValue) => void }) {
  const [value, setValue] = useState<PhoneValue>({ country: 'CA', national: '' });
  return (
    <FormField label="Phone" id="phone">
      <PhoneInput
        value={value}
        onChange={(next) => {
          setValue(next);
          onChange?.(next);
        }}
      />
    </FormField>
  );
}

describe('PhoneInput', () => {
  it('emits the country and national number, which compose to E.164', async () => {
    const onChange = vi.fn();
    render(<Harness onChange={onChange} />);

    await userEvent.type(screen.getByLabelText('Phone'), '9025550111');

    expect(onChange).toHaveBeenLastCalledWith({ country: 'CA', national: '9025550111' });
    expect(composeE164('CA', '9025550111')).toBe('+19025550111');
  });

  it('changes the region through the country selector', async () => {
    const onChange = vi.fn();
    render(<Harness onChange={onChange} />);

    await userEvent.selectOptions(screen.getByLabelText('Country calling code'), 'GB');

    expect(onChange).toHaveBeenLastCalledWith({ country: 'GB', national: '' });
  });

  it('is labelled and marks invalid state', () => {
    render(
      <FormField
        label="Phone"
        id="phone"
        error="Enter a valid phone number for the selected country."
      >
        <PhoneInput value={{ country: 'CA', national: '123' }} onChange={() => {}} />
      </FormField>,
    );

    const input = screen.getByLabelText('Phone');
    expect(input).toHaveAttribute('aria-invalid', 'true');
    expect(screen.getByRole('alert')).toHaveTextContent(
      'Enter a valid phone number for the selected country.',
    );
  });
});
