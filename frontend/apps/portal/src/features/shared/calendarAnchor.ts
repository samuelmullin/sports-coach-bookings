import type { CalendarEvent } from '@scb/ui';

/**
 * The date of the earliest event, used to open a calendar on the first
 * available date rather than today.
 */
export function firstEventDate(events: CalendarEvent[]): Date | undefined {
  let earliest: number | undefined;
  for (const event of events) {
    const time = Date.parse(event.startsAt);
    if (Number.isNaN(time)) continue;
    if (earliest === undefined || time < earliest) earliest = time;
  }
  return earliest === undefined ? undefined : new Date(earliest);
}
