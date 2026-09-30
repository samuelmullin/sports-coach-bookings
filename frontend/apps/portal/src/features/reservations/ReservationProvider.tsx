import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from 'react';
import { useToast } from '@scb/ui';
import {
  reservationQueryKey,
  useConvertReservation,
  useCreateReservation,
  useExtendReservation,
  useReleaseReservation,
  useReservationResource,
  type ConvertedBooking,
  type ReservationAssignmentInput,
  type ReservationCreateResult,
  type ReservationRecord,
  type ReservationSessionSummary,
} from '../../api/endpoints';
import { body, errorCode, errorMessage, responseData } from '../shared/api-utils';
import { friendlyError } from '../shared/errors';
import {
  clearReservationStorage,
  readReservation,
  writeReservation,
  type ReservationAssignment,
  type ReservationMethod,
  type ReservationOptionKind,
  type StoredReservation,
} from './reservation-store';

export type ReservationStatus = 'none' | 'active' | 'expired' | 'converting' | 'done';

/** Extend at most once per this window unless forced (form submits/idle button). */
const TOUCH_THROTTLE_MS = 15_000;
/** Warn when the user has been idle this long… */
const IDLE_WARN_MS = 8 * 60_000;
/** …or when this little time remains. */
const REMAINING_WARN_MS = 2 * 60_000;

export interface ReserveInput {
  offeringId?: string;
  optionKind: ReservationOptionKind;
  packId?: string;
  sessionIds: string[];
  sessions?: ReservationSessionSummary[];
}

export interface ReservationContextValue {
  reservation: StoredReservation | null;
  status: ReservationStatus;
  remainingMs: number;
  idleMs: number;
  shouldWarn: boolean;
  reserve: (input: ReserveInput) => Promise<StoredReservation>;
  touch: (options?: { force?: boolean }) => Promise<void>;
  release: () => Promise<void>;
  clear: () => void;
  convert: (assignments: ReservationAssignment[]) => Promise<ConvertedBooking[]>;
  setAssignments: (assignments: ReservationAssignment[]) => void;
  markExpired: () => void;
}

const ReservationContext = createContext<ReservationContextValue | null>(null);

function tokenHeaders(token: string | undefined): RequestInit | undefined {
  return token ? { headers: { 'x-reservation-token': token } } : undefined;
}

function toStored(record: {
  id: string;
  expires_at: string;
  last_activity_at?: string;
  sessions: ReservationSessionSummary[];
}): Pick<StoredReservation, 'expiresAt' | 'lastActivityAt' | 'sessions' | 'sessionIds'> {
  return {
    expiresAt: record.expires_at,
    lastActivityAt: record.last_activity_at ?? record.expires_at,
    sessions: record.sessions ?? [],
    sessionIds: (record.sessions ?? []).map((session) => session.session_id),
  };
}

export function ReservationProvider({ children }: { children: ReactNode }) {
  const { toast } = useToast();
  const [reservation, setReservation] = useState<StoredReservation | null>(() => readReservation());
  const [now, setNow] = useState(() => Date.now());
  const [converting, setConverting] = useState(false);
  const [done, setDone] = useState(false);
  const lastTouchRef = useRef(0);
  const skipVerifyIdRef = useRef<string | null>(null);
  const verifiedIdRef = useRef<string | null>(null);

  const token = reservation?.token;

  const createReservation = useCreateReservation();
  const extendReservation = useExtendReservation({ request: tokenHeaders(token) });
  const releaseReservation = useReleaseReservation({ request: tokenHeaders(token) });
  const convertReservation = useConvertReservation({ request: tokenHeaders(token) });

  const shouldVerify =
    Boolean(reservation?.id && reservation?.token) && skipVerifyIdRef.current !== reservation?.id;

  const showQuery = useReservationResource(reservation?.id ?? '', {
    query: {
      queryKey: reservationQueryKey(reservation?.id ?? ''),
      enabled: shouldVerify,
      retry: false,
    },
    request: tokenHeaders(token),
  });

  // Rehydrated reservations are verified against the server exactly once.
  useEffect(() => {
    if (!shouldVerify || !reservation) return;
    if (verifiedIdRef.current === reservation.id) return;
    if (showQuery.isError) {
      verifiedIdRef.current = reservation.id;
      const code = errorCode(showQuery.error);
      if (code === 'not_found' || code === 'unauthorized' || code === 'reservation_expired') {
        setReservation((current) =>
          current ? { ...current, expiresAt: new Date(0).toISOString() } : current,
        );
      }
      return;
    }
    const record = body<ReservationRecord>(showQuery);
    if (!record) return;
    verifiedIdRef.current = reservation.id;
    if (record.status !== 'active') {
      setReservation((current) =>
        current ? { ...current, expiresAt: new Date(0).toISOString() } : current,
      );
      return;
    }
    setReservation((current) =>
      current ? { ...current, ...toStored(record), assignments: current.assignments } : current,
    );
  }, [shouldVerify, reservation, showQuery]);

  // Tick the clock so countdowns and idle detection stay live.
  useEffect(() => {
    if (!reservation) return;
    const interval = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(interval);
  }, [reservation]);

  // Persist any state change (except the terminal `done` clearing below).
  useEffect(() => {
    if (reservation) writeReservation(reservation);
  }, [reservation]);

  const clear = useCallback(() => {
    clearReservationStorage();
    setReservation(null);
    setDone(false);
  }, []);

  const remainingMs = reservation ? Math.max(0, Date.parse(reservation.expiresAt) - now) : 0;
  const idleMs = reservation ? Math.max(0, now - Date.parse(reservation.lastActivityAt)) : 0;

  const status: ReservationStatus = useMemo(() => {
    if (converting) return 'converting';
    if (!reservation) return done ? 'done' : 'none';
    if (done) return 'done';
    if (remainingMs <= 0) return 'expired';
    return 'active';
  }, [converting, reservation, done, remainingMs]);

  const shouldWarn =
    status === 'active' && (idleMs >= IDLE_WARN_MS || remainingMs <= REMAINING_WARN_MS);

  const reserve = useCallback(
    async (input: ReserveInput): Promise<StoredReservation> => {
      const result = await createReservation.mutateAsync({
        data: { sessions: input.sessionIds, offering_id: input.offeringId ?? null },
      });
      const created = responseData<ReservationCreateResult>(result);
      if (!created?.id || !created.token) throw new Error('Could not reserve those sessions');

      const stored: StoredReservation = {
        id: created.id,
        token: created.token,
        offeringId: input.offeringId ?? created.offering_id ?? undefined,
        optionKind: input.optionKind,
        packId: input.packId,
        sessionIds: created.sessions.map((session) => session.session_id),
        sessions: created.sessions,
        expiresAt: created.expires_at,
        lastActivityAt: created.last_activity_at ?? new Date().toISOString(),
      };
      skipVerifyIdRef.current = stored.id;
      lastTouchRef.current = Date.now();
      clearReservationStorage();
      setDone(false);
      setReservation(stored);
      setNow(Date.now());
      return stored;
    },
    [createReservation],
  );

  const touch = useCallback(
    async (options?: { force?: boolean }): Promise<void> => {
      if (!reservation) return;
      if (status !== 'active' && status !== 'converting') return;
      const timestamp = Date.now();
      if (!options?.force && timestamp - lastTouchRef.current < TOUCH_THROTTLE_MS) return;
      lastTouchRef.current = timestamp;
      try {
        const result = await extendReservation.mutateAsync({ id: reservation.id });
        const extended = responseData<{ expires_at: string; last_activity_at: string }>(result);
        if (extended) {
          setReservation((current) =>
            current
              ? {
                  ...current,
                  expiresAt: extended.expires_at,
                  lastActivityAt: extended.last_activity_at,
                }
              : current,
          );
          setNow(Date.now());
        }
      } catch (error) {
        const code = errorCode(error);
        if (code === 'reservation_expired' || code === 'not_found') {
          setReservation((current) =>
            current ? { ...current, expiresAt: new Date(0).toISOString() } : current,
          );
        }
      }
    },
    [reservation, status, extendReservation],
  );

  const release = useCallback(async (): Promise<void> => {
    const current = reservation;
    if (current) {
      try {
        await releaseReservation.mutateAsync({ id: current.id });
      } catch {
        // Releasing is best-effort; the holds expire on their own.
      }
    }
    clearReservationStorage();
    setReservation(null);
    setDone(false);
  }, [reservation, releaseReservation]);

  const setAssignments = useCallback((assignments: ReservationAssignment[]) => {
    setReservation((current) => (current ? { ...current, assignments } : current));
  }, []);

  const markExpired = useCallback(() => {
    setReservation((current) =>
      current ? { ...current, expiresAt: new Date(0).toISOString() } : current,
    );
  }, []);

  const convert = useCallback(
    async (assignments: ReservationAssignment[]): Promise<ConvertedBooking[]> => {
      if (!reservation) throw new Error('No reservation to convert');
      setConverting(true);
      try {
        const payload: ReservationAssignmentInput[] = assignments.map((assignment) => ({
          session_id: assignment.session_id,
          player_id: assignment.player_id,
          method: assignment.method as ReservationMethod,
        }));
        const result = await convertReservation.mutateAsync({
          id: reservation.id,
          data: { assignments: payload },
        });
        const converted = responseData<{ bookings: ConvertedBooking[] }>(result);
        setDone(true);
        clearReservationStorage();
        setReservation(null);
        return converted?.bookings ?? [];
      } catch (error) {
        const code = errorCode(error);
        if (code === 'reservation_expired' || code === 'not_found') {
          setReservation((current) =>
            current ? { ...current, expiresAt: new Date(0).toISOString() } : current,
          );
        }
        throw error;
      } finally {
        setConverting(false);
      }
    },
    [reservation, convertReservation],
  );

  const value = useMemo<ReservationContextValue>(
    () => ({
      reservation,
      status,
      remainingMs,
      idleMs,
      shouldWarn,
      reserve,
      touch,
      release,
      clear,
      convert,
      setAssignments,
      markExpired,
    }),
    [
      reservation,
      status,
      remainingMs,
      idleMs,
      shouldWarn,
      reserve,
      touch,
      release,
      clear,
      convert,
      setAssignments,
      markExpired,
    ],
  );

  // Surface extend failures once, outside the render path.
  const lastErrorRef = useRef<unknown>(null);
  useEffect(() => {
    if (showQuery.isError && showQuery.error !== lastErrorRef.current) {
      lastErrorRef.current = showQuery.error;
      const code = errorCode(showQuery.error);
      if (code && code !== 'not_found' && code !== 'unauthorized') {
        toast({ title: friendlyError(code, errorMessage(showQuery.error)), variant: 'danger' });
      }
    }
  }, [showQuery.isError, showQuery.error, toast]);

  return <ReservationContext.Provider value={value}>{children}</ReservationContext.Provider>;
}

export function useReservation(): ReservationContextValue {
  const context = useContext(ReservationContext);
  if (!context) {
    throw new Error('useReservation must be used within <ReservationProvider>');
  }
  return context;
}

/** Like `useReservation` but returns `null` outside a provider (e.g. tests). */
export function useOptionalReservation(): ReservationContextValue | null {
  return useContext(ReservationContext);
}
