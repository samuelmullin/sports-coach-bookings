import { ChevronLeft, ChevronRight } from 'lucide-react';
import { useMemo, useState } from 'react';
import { format } from 'date-fns';
import { cn } from '../lib/cn';
import {
  addDays,
  addMonths,
  isSameDay,
  isSameMonth,
  monthWeeks,
  startOfMonth,
  weekDays,
} from '../lib/calendar-grid';
import { dateKeyInZone, formatTime } from '../format/datetime';
import { Badge } from './Badge';

export interface CalendarCapacity {
  booked: number;
  total: number;
}

export interface CalendarEvent {
  id: string;
  title: string;
  startsAt: string;
  endsAt: string;
  capacity?: CalendarCapacity;
  location?: string;
  color?: string;
}

export type CalendarView = 'month' | 'week' | 'agenda';

export interface CalendarProps {
  events: CalendarEvent[];
  timezone: string;
  view?: CalendarView;
  defaultView?: CalendarView;
  onViewChange?: (view: CalendarView) => void;
  anchorDate?: Date;
  onDateSelect?: (date: Date) => void;
  onEventClick?: (event: CalendarEvent) => void;
  className?: string;
}

const VIEW_LABELS: Record<CalendarView, string> = {
  month: 'Month',
  week: 'Week',
  agenda: 'Agenda',
};

export function CapacityBadge({ capacity }: { capacity: CalendarCapacity }) {
  const { booked, total } = capacity;
  const ratio = total > 0 ? booked / total : 0;
  const variant = booked >= total ? 'danger' : ratio >= 0.8 ? 'warning' : 'success';
  return (
    <Badge variant={variant} aria-label={`${booked} of ${total} spots booked`}>
      {booked}/{total}
    </Badge>
  );
}

function eventTimeLabel(event: CalendarEvent, timezone: string): string {
  return `${formatTime(event.startsAt, timezone)}–${formatTime(event.endsAt, timezone)}`;
}

export function Calendar({
  events,
  timezone,
  view,
  defaultView = 'month',
  onViewChange,
  anchorDate,
  onDateSelect,
  onEventClick,
  className,
}: CalendarProps) {
  const [internalView, setInternalView] = useState<CalendarView>(defaultView);
  const [anchor, setAnchor] = useState<Date>(anchorDate ?? new Date());
  const activeView = view ?? internalView;

  const eventsByDay = useMemo(() => {
    const map = new Map<string, CalendarEvent[]>();
    for (const event of events) {
      const key = dateKeyInZone(event.startsAt, timezone);
      const list = map.get(key) ?? [];
      list.push(event);
      map.set(key, list);
    }
    for (const list of map.values()) {
      list.sort((a, b) => new Date(a.startsAt).getTime() - new Date(b.startsAt).getTime());
    }
    return map;
  }, [events, timezone]);

  const changeView = (next: CalendarView) => {
    setInternalView(next);
    onViewChange?.(next);
  };

  const weeks = useMemo(() => monthWeeks(anchor), [anchor]);
  const days = useMemo(() => weekDays(anchor), [anchor]);

  const agendaDays = useMemo(() => {
    const monthStart = startOfMonth(anchor);
    const keys: { date: Date; events: CalendarEvent[] }[] = [];
    for (let i = 0; i < 31; i += 1) {
      const date = addDays(monthStart, i);
      if (!isSameMonth(date, anchor) && i > 0) break;
      const key = format(date, 'yyyy-MM-dd');
      const dayEvents = eventsByDay.get(key) ?? [];
      if (dayEvents.length > 0) keys.push({ date, events: dayEvents });
    }
    return keys;
  }, [anchor, eventsByDay]);

  return (
    <div
      className={cn('rounded-lg border border-border bg-surface text-foreground', className)}
      data-testid="calendar"
      data-view={activeView}
    >
      <div className="flex flex-wrap items-center justify-between gap-2 border-b border-border p-3">
        <div className="flex items-center gap-1">
          <button
            type="button"
            aria-label="Previous period"
            onClick={() =>
              setAnchor((current) =>
                activeView === 'week' ? addDays(current, -7) : addMonths(current, -1),
              )
            }
            className="rounded p-1 hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          >
            <ChevronLeft className="h-4 w-4" aria-hidden="true" />
          </button>
          <button
            type="button"
            onClick={() => setAnchor(new Date())}
            className="rounded px-2 py-1 text-sm hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          >
            Today
          </button>
          <button
            type="button"
            aria-label="Next period"
            onClick={() =>
              setAnchor((current) =>
                activeView === 'week' ? addDays(current, 7) : addMonths(current, 1),
              )
            }
            className="rounded p-1 hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
          >
            <ChevronRight className="h-4 w-4" aria-hidden="true" />
          </button>
        </div>

        <h2 className="text-sm font-semibold" aria-live="polite">
          {activeView === 'week'
            ? `${format(days[0], 'MMM d')} – ${format(days[6], 'MMM d, yyyy')}`
            : format(anchor, 'LLLL yyyy')}
        </h2>

        <div role="tablist" aria-label="Calendar view" className="flex gap-1">
          {(Object.keys(VIEW_LABELS) as CalendarView[]).map((option) => (
            <button
              key={option}
              type="button"
              role="tab"
              aria-selected={activeView === option}
              onClick={() => changeView(option)}
              className={cn(
                'rounded px-2 py-1 text-xs font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                activeView === option ? 'bg-primary text-primary-foreground' : 'hover:bg-muted',
              )}
            >
              {VIEW_LABELS[option]}
            </button>
          ))}
        </div>
      </div>

      {activeView === 'month' ? (
        <div className="p-3">
          <div className="grid grid-cols-7 gap-1 text-center text-xs text-muted-foreground">
            {['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((label) => (
              <span key={label}>{label}</span>
            ))}
          </div>
          <div className="mt-1 grid grid-cols-7 gap-1">
            {weeks.flat().map((day) => {
              const key = format(day, 'yyyy-MM-dd');
              const dayEvents = eventsByDay.get(key) ?? [];
              const visible = dayEvents.slice(0, 2);
              return (
                <div
                  key={day.toISOString()}
                  role="button"
                  tabIndex={0}
                  onClick={() => onDateSelect?.(day)}
                  onKeyDown={(clickEvent) => {
                    if (clickEvent.key === 'Enter' || clickEvent.key === ' ') {
                      clickEvent.preventDefault();
                      onDateSelect?.(day);
                    }
                  }}
                  className={cn(
                    'flex min-h-[84px] cursor-pointer flex-col items-stretch gap-1 rounded-md border border-border p-1 text-left hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                    !isSameMonth(day, anchor) && 'opacity-50',
                    isSameDay(day, new Date()) && 'ring-1 ring-primary',
                  )}
                >
                  <span className="text-xs font-medium">{format(day, 'd')}</span>
                  {visible.map((event) => (
                    <button
                      key={event.id}
                      type="button"
                      onClick={(clickEvent) => {
                        clickEvent.stopPropagation();
                        onEventClick?.(event);
                      }}
                      className="truncate rounded bg-muted px-1 py-0.5 text-left text-[10px] hover:bg-primary/10 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                      title={`${event.title} ${eventTimeLabel(event, timezone)}`}
                    >
                      {formatTime(event.startsAt, timezone)} {event.title}
                    </button>
                  ))}
                  {dayEvents.length > 2 ? (
                    <span className="text-[10px] text-muted-foreground">
                      +{dayEvents.length - 2} more
                    </span>
                  ) : null}
                </div>
              );
            })}
          </div>
        </div>
      ) : null}

      {activeView === 'week' ? (
        <div className="grid grid-cols-1 divide-y divide-border sm:grid-cols-7 sm:divide-x sm:divide-y-0">
          {days.map((day) => {
            const key = format(day, 'yyyy-MM-dd');
            const dayEvents = eventsByDay.get(key) ?? [];
            return (
              <div key={day.toISOString()} className="min-h-[120px] p-2">
                <div className="mb-2 text-xs font-medium">{format(day, 'EEE d')}</div>
                <div className="flex flex-col gap-1">
                  {dayEvents.map((event) => (
                    <button
                      key={event.id}
                      type="button"
                      onClick={() => onEventClick?.(event)}
                      className="w-full rounded-md border border-border bg-background p-2 text-left text-xs hover:border-primary/50 hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                    >
                      <div className="flex items-center justify-between gap-1">
                        <span className="font-medium">{event.title}</span>
                        {event.capacity ? <CapacityBadge capacity={event.capacity} /> : null}
                      </div>
                      <div className="text-muted-foreground">{eventTimeLabel(event, timezone)}</div>
                      {event.location ? (
                        <div className="text-muted-foreground">{event.location}</div>
                      ) : null}
                    </button>
                  ))}
                  {dayEvents.length === 0 ? (
                    <span className="text-xs text-muted-foreground">—</span>
                  ) : null}
                </div>
              </div>
            );
          })}
        </div>
      ) : null}

      {activeView === 'agenda' ? (
        <ul className="divide-y divide-border">
          {agendaDays.length === 0 ? (
            <li className="p-4 text-sm text-muted-foreground">No events</li>
          ) : (
            agendaDays.map(({ date, events: dayEvents }) => (
              <li key={date.toISOString()} className="p-3">
                <div className="mb-2 text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                  {format(date, 'EEEE, MMMM d')}
                </div>
                <ul className="flex flex-col gap-2">
                  {dayEvents.map((event) => (
                    <li key={event.id}>
                      <button
                        type="button"
                        onClick={() => onEventClick?.(event)}
                        className="flex w-full items-center justify-between gap-2 rounded-md border border-border p-2 text-left text-sm hover:border-primary/50 hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                      >
                        <div>
                          <div className="font-medium">{event.title}</div>
                          <div className="text-xs text-muted-foreground">
                            {eventTimeLabel(event, timezone)}
                            {event.location ? ` · ${event.location}` : ''}
                          </div>
                        </div>
                        {event.capacity ? <CapacityBadge capacity={event.capacity} /> : null}
                      </button>
                    </li>
                  ))}
                </ul>
              </li>
            ))
          )}
        </ul>
      ) : null}
    </div>
  );
}
