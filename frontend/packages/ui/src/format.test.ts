import { describe, expect, it } from 'vitest';
import { formatTenantSlug } from './format';

describe('formatTenantSlug', () => {
  it('lowercases and trims the slug', () => {
    expect(formatTenantSlug('  Demo ')).toBe('demo');
  });
});
