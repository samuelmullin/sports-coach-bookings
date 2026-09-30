/**
 * Maps backend engine error codes to friendly customer-facing copy.
 * Codes come from `ApiError.code` (see `{ error: { code, message } }`).
 */
const ENGINE_ERRORS: Record<string, string> = {
  session_full: 'This session just filled up. Try another time.',
  invalid_session: 'One of those sessions is no longer available. Pick a different time.',
  reservation_expired: 'Your reserved session times were released due to inactivity.',
  released: 'This reservation has already been released.',
  waivers_required: 'Sign the required waivers for this player before booking.',
  player_conflict: 'This player is already booked into another session at that time.',
  insufficient_credits: 'This player does not have enough eligible sessions.',
  too_late: 'Online booking has closed for this session. Contact the club for help.',
  too_early: 'This session is not open for booking yet.',
  not_bookable: 'This session cannot be booked online.',
  age_ineligible: 'This player is outside the age range for this session.',
  contacts_required: 'Add at least one emergency contact before booking.',
  credits_not_eligible: 'Your sessions are not valid for this offering.',
  package_limit_reached: 'Your household has reached the limit for this package.',
  held: 'This session is temporarily held in your cart.',
  not_found: 'We could not find that record.',
  forbidden: 'You do not have access to that.',
  invalid: 'Please check the highlighted fields and try again.',
};

export function friendlyError(code: string | undefined, fallback: string): string {
  if (code && ENGINE_ERRORS[code]) return ENGINE_ERRORS[code];
  return fallback;
}
