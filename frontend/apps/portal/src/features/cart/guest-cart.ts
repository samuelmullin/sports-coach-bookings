import { useSyncExternalStore } from 'react';

export type GuestLineType = 'package' | 'product' | 'drop_in';

export interface GuestLineSnapshot {
  title: string;
  subtitle?: string;
  priceMinor?: number;
  currency?: string;
  sessionId?: string;
  startsAt?: string;
  venueName?: string;
}

export interface GuestLine {
  id: string;
  type: GuestLineType;
  ref_id: string;
  quantity: number;
  snapshot: GuestLineSnapshot;
}

const STORAGE_PREFIX = 'scb:guest-cart:';
const EMPTY: GuestLine[] = [];
const listeners = new Set<() => void>();

let cache: GuestLine[] = EMPTY;
let cacheKey: string | null = null;
let storageListenerAttached = false;

/** Storage key scoped per tenant host so one browser can hold several carts. */
export function guestCartStorageKey(host?: string): string {
  const resolved = host ?? (typeof window !== 'undefined' ? (window.location?.host ?? '') : '');
  return `${STORAGE_PREFIX}${resolved}`;
}

export function guestLineId(type: GuestLineType, refId: string): string {
  return `${type}:${refId}`;
}

function getStorage(): Storage | null {
  if (typeof window === 'undefined') return null;
  try {
    return window.localStorage ?? null;
  } catch {
    return null;
  }
}

function isLineType(value: unknown): value is GuestLineType {
  return value === 'package' || value === 'product' || value === 'drop_in';
}

function isGuestLine(value: unknown): value is GuestLine {
  if (!value || typeof value !== 'object') return false;
  const line = value as Partial<GuestLine>;
  return (
    typeof line.id === 'string' &&
    isLineType(line.type) &&
    typeof line.ref_id === 'string' &&
    typeof line.quantity === 'number' &&
    line.quantity > 0 &&
    Boolean(line.snapshot) &&
    typeof line.snapshot?.title === 'string'
  );
}

function loadFromStorage(): GuestLine[] {
  const storage = getStorage();
  if (!storage) return EMPTY;
  try {
    const raw = storage.getItem(guestCartStorageKey());
    if (!raw) return EMPTY;
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return EMPTY;
    return parsed.filter(isGuestLine).map((line) => ({
      ...line,
      snapshot: { ...line.snapshot },
    }));
  } catch {
    return EMPTY;
  }
}

function emit(): void {
  for (const listener of listeners) listener();
}

function ensureStorageListener(): void {
  if (storageListenerAttached || typeof window === 'undefined') return;
  storageListenerAttached = true;
  window.addEventListener('storage', (event) => {
    if (event.key !== null && !event.key.startsWith(STORAGE_PREFIX)) return;
    cache = loadFromStorage();
    cacheKey = guestCartStorageKey();
    emit();
  });
}

export function readGuestCart(): GuestLine[] {
  const key = guestCartStorageKey();
  if (key !== cacheKey) {
    cache = loadFromStorage();
    cacheKey = key;
  }
  return cache;
}

function write(lines: GuestLine[]): void {
  const storage = getStorage();
  const key = guestCartStorageKey();
  if (storage) {
    try {
      if (lines.length === 0) storage.removeItem(key);
      else storage.setItem(key, JSON.stringify(lines));
    } catch {
      // Storage may be full or blocked; keep the in-memory cart usable.
    }
  }
  cache = lines;
  cacheKey = key;
  emit();
}

export function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  ensureStorageListener();
  return () => {
    listeners.delete(listener);
  };
}

export function addGuestLine(line: GuestLine): void {
  const lines = [...readGuestCart()];
  const index = lines.findIndex((existing) => existing.id === line.id);
  if (index >= 0) {
    const existing = lines[index];
    lines[index] = {
      ...existing,
      quantity: existing.quantity + line.quantity,
      snapshot: { ...existing.snapshot, ...line.snapshot },
    };
  } else {
    lines.push({ ...line, snapshot: { ...line.snapshot } });
  }
  write(lines);
}

export function removeGuestLine(id: string): void {
  write(readGuestCart().filter((line) => line.id !== id));
}

export function updateGuestQuantity(id: string, quantity: number): void {
  const next = Math.max(1, Math.floor(quantity));
  write(readGuestCart().map((line) => (line.id === id ? { ...line, quantity: next } : line)));
}

export function clearGuestCart(): void {
  write([]);
}

function getServerSnapshot(): GuestLine[] {
  return EMPTY;
}

export function useGuestCart(): GuestLine[] {
  return useSyncExternalStore(subscribe, readGuestCart, getServerSnapshot);
}
