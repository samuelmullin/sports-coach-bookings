import { Navigate, useParams } from 'react-router-dom';
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

/**
 * Every offering requires picking a date/time, so the offering page and its
 * schedule page are collapsed: `/offerings/:id` redirects to the schedule.
 */
export function OfferingRedirect() {
  const { offeringId } = useParams<{ offeringId: string }>();
  return <Navigate to={`/offerings/${offeringId}/schedule`} replace />;
}
