import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { QueryState } from '../QueryState';

// Regression: the loading skeleton was a bare <div aria-label="Loading">, which axe
// rejects (aria-label is not allowed on a div with no role) and which screen readers
// ignore. It must be a labelled live status region.
describe('QueryState loading', () => {
  it('exposes the skeleton as a labelled busy status region', () => {
    render(
      <QueryState loading>
        <p>content</p>
      </QueryState>,
    );

    const status = screen.getByRole('status', { name: 'Loading' });
    expect(status).toHaveAttribute('aria-busy', 'true');
    expect(screen.queryByText('content')).not.toBeInTheDocument();
  });
});
