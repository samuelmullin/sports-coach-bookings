/**
 * Per-tenant localStorage store for the single active guest reservation.
 *
 * The reservation token is an opaque bearer credential; it lives here so a
 * page reload (for example returning from the hosted payment page) can
 * rehydrate the hold and verify it via `GET /api/portal/reservations/:id`.
 */

export type ReservationOptionKind = 'single' | 'pack';

export type ReservationMethod = 'credits' | 'paid';

export interface ReservationSessionSummary {
  session_id: string;
  starts_at?: string | null;
  ends_at?: string | null;
}

export interface ReservationAssignment {
  session_id: string;
  player_id: string;
  method: ReservationMethod;
}

export interface StoredReservation {
  id: string;
  token: string;
  offeringId?: string;
  optionKind: ReservationOptionKind;
  packId?: string;
  sessionIds: string[];
  sessions: ReservationSessionSummary[];
  expiresAt: string;
  lastActivityAt: string;
  /** Assignments persisted so a deferred (pack) convert can run after payment. */
  assignments?: ReservationAssignment[];
}

const STORAGE_PREFIX = 'scb:reservation:';

/** Storage key scoped per tenant host, mirroring the guest cart. */
export function reservationStorageKey(host?: string): string {
  const resolved = host ?? (typeof window !== 'undefined' ? (window.location?.host ?? '') : '');
  return `${STORAGE_PREFIX}${resolved}`;
}

function getStorage(): Storage | null {
  if (typeof window === 'undefined') return null;
  try {
    return window.localStorage ?? null;
  } catch {
    return null;
  }
}

function isStoredReservation(value: unknown): value is StoredReservation {
  if (!value || typeof value !== 'object') return false;
  const reservation = value as Partial<StoredReservation>;
  return (
    typeof reservation.id === 'string' &&
    typeof reservation.token === 'string' &&
    (reservation.optionKind === 'single' || reservation.optionKind === 'pack') &&
    Array.isArray(reservation.sessionIds) &&
    typeof reservation.expiresAt === 'string' &&
    typeof reservation.lastActivityAt === 'string'
  );
}

export function readReservation(): StoredReservation | null {
  const storage = getStorage();
  if (!storage) return null;
  try {
    const raw = storage.getItem(reservationStorageKey());
    if (!raw) return null;
    const parsed: unknown = JSON.parse(raw);
    if (!isStoredReservation(parsed)) return null;
    return {
      ...parsed,
      sessionIds: [...parsed.sessionIds],
      sessions: parsed.sessions ?? [],
      assignments: parsed.assignments ? [...parsed.assignments] : undefined,
    };
  } catch {
    return null;
  }
}

export function writeReservation(reservation: StoredReservation | null): void {
  const storage = getStorage();
  if (!storage) return;
  const key = reservationStorageKey();
  try {
    if (!reservation) storage.removeItem(key);
    else storage.setItem(key, JSON.stringify(reservation));
  } catch {
    // Storage may be full or blocked; the in-memory state still works.
  }
}

export function clearReservationStorage(): void {
  writeReservation(null);
}
