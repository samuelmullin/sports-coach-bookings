import * as Popover from '@radix-ui/react-popover';
import { CalendarDays, ChevronLeft, ChevronRight } from 'lucide-react';
import { useState } from 'react';
import { format } from 'date-fns';
import { cn } from '../lib/cn';
import { addMonths, isSameDay, isSameMonth, monthWeeks } from '../lib/calendar-grid';

const WEEKDAY_LABELS = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

export interface DatePickerProps {
  value?: Date;
  onChange?: (date: Date | undefined) => void;
  placeholder?: string;
  disabled?: boolean;
  id?: string;
  className?: string;
  'aria-label'?: string;
}

export function DatePicker({
  value,
  onChange,
  placeholder = 'Pick a date',
  disabled,
  id,
  className,
  'aria-label': ariaLabel,
}: DatePickerProps) {
  const [open, setOpen] = useState(false);
  const [anchor, setAnchor] = useState<Date>(value ?? new Date());
  const weeks = monthWeeks(anchor);

  return (
    <Popover.Root
      open={open}
      onOpenChange={(next) => {
        setOpen(next);
        if (next) setAnchor(value ?? new Date());
      }}
    >
      <Popover.Trigger asChild>
        <button
          id={id}
          type="button"
          disabled={disabled}
          aria-label={ariaLabel ?? placeholder}
          className={cn(
            'flex h-10 w-full items-center justify-between rounded-md border border-border bg-surface px-3 py-2 text-sm text-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background disabled:cursor-not-allowed disabled:opacity-50',
            className,
          )}
        >
          <span className={cn(!value && 'text-muted-foreground')}>
            {value ? format(value, 'PP') : placeholder}
          </span>
          <CalendarDays className="ml-2 h-4 w-4 opacity-60" aria-hidden="true" />
        </button>
      </Popover.Trigger>
      <Popover.Portal>
        <Popover.Content
          align="start"
          sideOffset={4}
          className="z-50 w-72 rounded-md border border-border bg-surface p-3 shadow-md"
        >
          <div className="mb-2 flex items-center justify-between">
            <button
              type="button"
              aria-label="Previous month"
              onClick={() => setAnchor((current) => addMonths(current, -1))}
              className="rounded p-1 hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            >
              <ChevronLeft className="h-4 w-4" aria-hidden="true" />
            </button>
            <span className="text-sm font-medium" aria-live="polite">
              {format(anchor, 'LLLL yyyy')}
            </span>
            <button
              type="button"
              aria-label="Next month"
              onClick={() => setAnchor((current) => addMonths(current, 1))}
              className="rounded p-1 hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            >
              <ChevronRight className="h-4 w-4" aria-hidden="true" />
            </button>
          </div>
          <div className="grid grid-cols-7 gap-1 text-center text-xs text-muted-foreground">
            {WEEKDAY_LABELS.map((label) => (
              <span key={label}>{label}</span>
            ))}
          </div>
          <div className="mt-1 grid grid-cols-7 gap-1" role="grid">
            {weeks.flat().map((day) => {
              const isSelected = value ? isSameDay(day, value) : false;
              return (
                <button
                  key={day.toISOString()}
                  type="button"
                  role="gridcell"
                  aria-selected={isSelected}
                  aria-current={isSameDay(day, new Date()) ? 'date' : undefined}
                  onClick={() => {
                    onChange?.(day);
                    setOpen(false);
                  }}
                  className={cn(
                    'h-8 w-8 rounded-md text-sm hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                    !isSameMonth(day, anchor) && 'text-muted-foreground',
                    isSelected && 'bg-primary text-primary-foreground hover:bg-primary',
                  )}
                >
                  {format(day, 'd')}
                </button>
              );
            })}
          </div>
        </Popover.Content>
      </Popover.Portal>
    </Popover.Root>
  );
}
