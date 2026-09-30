import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { GuestLine } from '../guest-cart';

type GuestCartModule = typeof import('../guest-cart');

async function freshStore(): Promise<GuestCartModule> {
  vi.resetModules();
  return import('../guest-cart');
}

function packageLine(overrides: Partial<GuestLine> = {}): GuestLine {
  return {
    id: 'package:p1',
    type: 'package',
    ref_id: 'p1',
    quantity: 1,
    snapshot: { title: 'Summer package', priceMinor: 20000, currency: 'CAD' },
    ...overrides,
  };
}

describe('guest cart store', () => {
  beforeEach(() => {
    window.localStorage.clear();
  });

  it('adds, updates and removes lines, persisting to localStorage', async () => {
    const store = await freshStore();
    store.addGuestLine(packageLine());
    expect(store.readGuestCart()).toHaveLength(1);
    expect(window.localStorage.getItem(store.guestCartStorageKey())).toContain('Summer package');

    store.addGuestLine(packageLine());
    expect(store.readGuestCart()[0]?.quantity).toBe(2);

    store.updateGuestQuantity('package:p1', 5);
    expect(store.readGuestCart()[0]?.quantity).toBe(5);

    store.removeGuestLine('package:p1');
    expect(store.readGuestCart()).toHaveLength(0);
    expect(window.localStorage.getItem(store.guestCartStorageKey())).toBeNull();
  });

  it('keeps a stable local id per type and ref', async () => {
    const store = await freshStore();
    expect(store.guestLineId('product', 'variant-1')).toBe('product:variant-1');
  });

  it('is scoped by host so tenants do not share carts', async () => {
    const store = await freshStore();
    expect(store.guestCartStorageKey('a.test')).toBe('scb:guest-cart:a.test');
    expect(store.guestCartStorageKey('a.test')).not.toBe(store.guestCartStorageKey('b.test'));

    store.addGuestLine(packageLine());
    window.localStorage.setItem(
      store.guestCartStorageKey('other.test'),
      JSON.stringify([packageLine({ id: 'product:v9', type: 'product', ref_id: 'v9' })]),
    );

    const current = store.readGuestCart();
    expect(current).toHaveLength(1);
    expect(current[0]?.type).toBe('package');
  });

  it('persists across reloads', async () => {
    const store = await freshStore();
    store.addGuestLine(packageLine({ quantity: 3 }));

    const reloaded = await freshStore();
    const lines = reloaded.readGuestCart();
    expect(lines).toHaveLength(1);
    expect(lines[0]?.quantity).toBe(3);
    expect(lines[0]?.snapshot.title).toBe('Summer package');
  });

  it('handles invalid JSON and non-array payloads', async () => {
    const invalidJson = await freshStore();
    window.localStorage.setItem(invalidJson.guestCartStorageKey(), '{not-json');
    expect(invalidJson.readGuestCart()).toEqual([]);

    window.localStorage.clear();
    const nonArray = await freshStore();
    window.localStorage.setItem(nonArray.guestCartStorageKey(), JSON.stringify({ nope: true }));
    expect(nonArray.readGuestCart()).toEqual([]);
  });

  it('clears the key when the last line is removed', async () => {
    const store = await freshStore();
    store.addGuestLine(packageLine());
    store.clearGuestCart();
    expect(store.readGuestCart()).toEqual([]);
    expect(window.localStorage.getItem(store.guestCartStorageKey())).toBeNull();
  });
});
