import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { FormField } from '../FormField';
import { Input } from '../Input';

describe('FormField + Input', () => {
  it('associates the label with the input', () => {
    render(
      <FormField label="Email" id="email">
        <Input type="email" />
      </FormField>,
    );
    expect(screen.getByLabelText('Email')).toBeInTheDocument();
  });

  it('exposes help text via aria-describedby', () => {
    render(
      <FormField label="Slug" help="Lowercase letters only" id="slug">
        <Input />
      </FormField>,
    );
    const input = screen.getByLabelText('Slug');
    expect(input).toHaveAccessibleDescription('Lowercase letters only');
  });

  it('exposes errors with role=alert and aria-invalid', () => {
    render(
      <FormField label="Email" error="Email is required" id="email">
        <Input type="email" />
      </FormField>,
    );
    expect(screen.getByRole('alert')).toHaveTextContent('Email is required');
    expect(screen.getByLabelText('Email')).toHaveAttribute('aria-invalid', 'true');
  });

  it('marks required fields', () => {
    render(
      <FormField label="Name" required id="name">
        <Input />
      </FormField>,
    );
    expect(screen.getByText('*')).toBeInTheDocument();
  });
});
