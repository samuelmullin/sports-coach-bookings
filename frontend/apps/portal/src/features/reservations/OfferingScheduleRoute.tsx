import { GuestReservePage } from './GuestReservePage';

/**
 * `/offerings/:offeringId/schedule` is public. Everyone goes through the same
 * "select sessions → hold → complete your booking (assign players)" flow:
 * anonymous visitors are sent to sign-in/sign-up only after choosing sessions;
 * signed-in customers skip straight to the completion step.
 */
export function OfferingScheduleRoute() {
  return <GuestReservePage />;
}
