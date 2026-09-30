import type { PlayerResponse } from '../../api/endpoints';

/** Age in whole years for a date-of-birth string, relative to `now`. */
export function ageFromDateOfBirth(dateOfBirth: string, now: Date = new Date()): number {
  const dob = new Date(dateOfBirth);
  let age = now.getFullYear() - dob.getFullYear();
  const monthDiff = now.getMonth() - dob.getMonth();
  if (monthDiff < 0 || (monthDiff === 0 && now.getDate() < dob.getDate())) {
    age -= 1;
  }
  return age;
}

export function playerAge(player: PlayerResponse, now: Date = new Date()): number {
  if (typeof player.age === 'number') return player.age;
  return ageFromDateOfBirth(player.date_of_birth, now);
}

export function isAgeEligible(
  player: PlayerResponse,
  minAge?: number | null,
  maxAge?: number | null,
): boolean {
  if (player.age === undefined && !player.date_of_birth) return true;
  const age = playerAge(player);
  if (typeof minAge === 'number' && age < minAge) return false;
  if (typeof maxAge === 'number' && age > maxAge) return false;
  return true;
}
