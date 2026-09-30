import { formatInTimeZone, fromZonedTime, toZonedTime } from 'date-fns-tz';

export function toZonedDate(instant: Date | string, timeZone: string): Date {
  return toZonedTime(typeof instant === 'string' ? new Date(instant) : instant, timeZone);
}

export function zonedDateToUtc(zoned: Date, timeZone: string): Date {
  return fromZonedTime(zoned, timeZone);
}

export function formatDateTime(instant: Date | string, timeZone: string, locale = 'en-CA'): string {
  const date = typeof instant === 'string' ? new Date(instant) : instant;
  return new Intl.DateTimeFormat(locale, {
    timeZone,
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(date);
}

export function formatDate(instant: Date | string, timeZone: string, locale = 'en-CA'): string {
  const date = typeof instant === 'string' ? new Date(instant) : instant;
  return new Intl.DateTimeFormat(locale, {
    timeZone,
    dateStyle: 'medium',
  }).format(date);
}

export function formatTime(instant: Date | string, timeZone: string, locale = 'en-CA'): string {
  const date = typeof instant === 'string' ? new Date(instant) : instant;
  return new Intl.DateTimeFormat(locale, {
    timeZone,
    timeStyle: 'short',
  }).format(date);
}

export function formatTimeRange(
  start: Date | string,
  end: Date | string,
  timeZone: string,
  locale = 'en-CA',
): string {
  return `${formatTime(start, timeZone, locale)} – ${formatTime(end, timeZone, locale)}`;
}

export function formatInZone(instant: Date | string, timeZone: string, pattern: string): string {
  const date = typeof instant === 'string' ? new Date(instant) : instant;
  return formatInTimeZone(date, timeZone, pattern);
}

export function dateKeyInZone(instant: Date | string, timeZone: string): string {
  return formatInZone(instant, timeZone, 'yyyy-MM-dd');
}

export { formatInTimeZone, toZonedTime, fromZonedTime };
