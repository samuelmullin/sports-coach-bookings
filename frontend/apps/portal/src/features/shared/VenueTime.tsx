import { Clock } from 'lucide-react';
import { formatInZone } from '@scb/ui';

/**
 * Renders an instant in the venue timezone with the timezone abbreviation,
 * plus a note when the browser is in a different zone.
 */
export function VenueTime({
  instant,
  timezone,
  pattern = 'EEE MMM d, h:mm a zzz',
  className,
}: {
  instant: string | Date;
  timezone: string;
  pattern?: string;
  className?: string;
}) {
  return (
    <time
      dateTime={typeof instant === 'string' ? instant : instant.toISOString()}
      className={className}
    >
      {formatInZone(instant, timezone, pattern)}
    </time>
  );
}

export function TimezoneNote({ timezone }: { timezone: string }) {
  if (typeof Intl === 'undefined') return null;
  const browserZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
  if (!browserZone || browserZone === timezone) return null;
  return (
    <p className="flex items-center gap-1 text-xs text-muted-foreground">
      <Clock className="h-3.5 w-3.5" aria-hidden="true" />
      Times are shown in the venue timezone ({timezone}).
    </p>
  );
}
