import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it } from 'vitest';
import { SiteLink } from '../SiteLink';

describe('SiteLink', () => {
  it('supports internal and HTTPS links', () => {
    const { rerender } = render(
      <MemoryRouter>
        <SiteLink href="/schedule">Schedule</SiteLink>
      </MemoryRouter>,
    );
    expect(screen.getByRole('link', { name: 'Schedule' })).toHaveAttribute('href', '/schedule');

    rerender(
      <MemoryRouter>
        <SiteLink href="https://example.test">Sponsor</SiteLink>
      </MemoryRouter>,
    );
    expect(screen.getByRole('link', { name: 'Sponsor' })).toHaveAttribute(
      'href',
      'https://example.test',
    );
  });

  it('does not render executable URL schemes', () => {
    render(
      <MemoryRouter>
        <SiteLink href="javascript:alert(1)">Unsafe</SiteLink>
      </MemoryRouter>,
    );
    expect(screen.queryByRole('link', { name: 'Unsafe' })).not.toBeInTheDocument();
  });
});
