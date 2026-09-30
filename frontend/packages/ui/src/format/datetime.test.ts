import { describe, expect, it } from 'vitest';
import {
  dateKeyInZone,
  formatDate,
  formatTime,
  formatTimeRange,
  toZonedDate,
  zonedDateToUtc,
} from './datetime';

describe('datetime helpers', () => {
  const instant = '2026-03-10T23:30:00Z';

  it('computes the date key in the target timezone', () => {
    expect(dateKeyInZone(instant, 'UTC')).toBe('2026-03-10');
    expect(dateKeyInZone(instant, 'America/Vancouver')).toBe('2026-03-10');
    expect(dateKeyInZone('2026-03-11T02:00:00Z', 'America/Vancouver')).toBe('2026-03-10');
  });

  it('formats time in the venue timezone', () => {
    expect(formatTime(instant, 'UTC')).toMatch(/11:30/);
    // March 10 2026 is after the DST switch, so Toronto is UTC-4.
    expect(formatTime(instant, 'America/Toronto')).toMatch(/7:30/);
  });

  it('formats a time range', () => {
    const range = formatTimeRange(instant, '2026-03-11T00:30:00Z', 'UTC');
    expect(range).toContain('–');
  });

  it('formats a date', () => {
    expect(formatDate(instant, 'UTC')).toMatch(/2026/);
  });

  it('round-trips between zoned and UTC', () => {
    const zoned = toZonedDate('2026-03-10T14:00:00Z', 'America/Toronto');
    expect(zoned.getHours()).toBe(10);
    const utc = zonedDateToUtc(zoned, 'America/Toronto');
    expect(utc.toISOString()).toBe('2026-03-10T14:00:00.000Z');
  });
});
