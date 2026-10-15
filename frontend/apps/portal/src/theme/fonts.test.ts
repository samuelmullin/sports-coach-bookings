import { describe, expect, it } from 'vitest';
import { FONT_OPTIONS } from '@scb/ui';
import { loadTenantFont } from './fonts';

describe('loadTenantFont', () => {
  it('has a loader for every selectable web font (system needs none)', async () => {
    for (const { value } of FONT_OPTIONS) {
      await expect(loadTenantFont(value)).resolves.not.toThrow();
    }
  });

  it('is a no-op for system, unknown, and missing keys', async () => {
    await expect(loadTenantFont('system')).resolves.toBeUndefined();
    await expect(loadTenantFont('comic_sans')).resolves.toBeUndefined();
    await expect(loadTenantFont(undefined)).resolves.toBeUndefined();
  });
});
