import {
  addDays,
  addMonths,
  endOfMonth,
  endOfWeek,
  isSameDay,
  isSameMonth,
  startOfMonth,
  startOfWeek,
} from 'date-fns';

export function monthWeeks(anchor: Date, weekStartsOn: 0 | 1 = 1): Date[][] {
  const first = startOfWeek(startOfMonth(anchor), { weekStartsOn });
  const last = endOfWeek(endOfMonth(anchor), { weekStartsOn });
  const weeks: Date[][] = [];
  let cursor = first;
  while (cursor <= last) {
    const week: Date[] = [];
    for (let i = 0; i < 7; i += 1) {
      week.push(cursor);
      cursor = addDays(cursor, 1);
    }
    weeks.push(week);
  }
  return weeks;
}

export function weekDays(anchor: Date, weekStartsOn: 0 | 1 = 1): Date[] {
  const first = startOfWeek(anchor, { weekStartsOn });
  return Array.from({ length: 7 }, (_, index) => addDays(first, index));
}

export {
  addDays,
  addMonths,
  isSameDay,
  isSameMonth,
  startOfMonth,
  endOfMonth,
  startOfWeek,
  endOfWeek,
};
