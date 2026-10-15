/**
 * Remembers an in-app "return to" path across a detour (add a contact, sign a
 * waiver, fill in a profile) so the customer can resume what they were doing.
 * Stored per tab; only same-origin absolute paths are honoured.
 */
const KEY = 'scb.returnTo';

function isSafe(value: unknown): value is string {
  return typeof value === 'string' && value.startsWith('/') && !value.startsWith('//');
}

export function setReturnTo(path: string): void {
  if (!isSafe(path)) return;
  try {
    sessionStorage.setItem(KEY, path);
  } catch {
    // Storage can be unavailable (private mode); the detour just has no shortcut back.
  }
}

export function readReturnTo(): string | undefined {
  try {
    const value = sessionStorage.getItem(KEY);
    return isSafe(value) ? value : undefined;
  } catch {
    return undefined;
  }
}

export function clearReturnTo(): void {
  try {
    sessionStorage.removeItem(KEY);
  } catch {
    // ignore
  }
}
