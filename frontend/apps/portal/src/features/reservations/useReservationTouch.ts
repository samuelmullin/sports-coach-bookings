import { useCallback } from 'react';
import { useOptionalReservation } from './ReservationProvider';

/**
 * Returns a function to call on a successful form submit while a guest
 * reservation is active. It extends (touches) the hold so the customer gets a
 * fresh 10 minutes as they move through sign-up and profile forms.
 */
export function useReservationTouch(): () => Promise<void> {
  const context = useOptionalReservation();
  const touch = context?.touch;
  const status = context?.status;

  return useCallback(async () => {
    if (status !== 'active' || !touch) return;
    try {
      await touch({ force: true });
    } catch {
      // Extending is best-effort; the reservation will expire on its own.
    }
  }, [status, touch]);
}
