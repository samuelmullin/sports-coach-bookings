import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { Calendar, type CalendarEvent } from '../Calendar';

const events: CalendarEvent[] = [
  {
    id: 'e1',
    title: 'U10 Skills',
    startsAt: '2026-03-10T14:00:00Z',
    endsAt: '2026-03-10T15:00:00Z',
    location: 'Field A',
    capacity: { booked: 5, total: 10 },
  },
  {
    id: 'e2',
    title: 'U12 Match',
    startsAt: '2026-03-11T18:30:00Z',
    endsAt: '2026-03-11T20:00:00Z',
    capacity: { booked: 12, total: 12 },
  },
];

describe('Calendar', () => {
  it('renders a month grid with events', () => {
    render(
      <Calendar
        events={events}
        timezone="America/Toronto"
        defaultView="month"
        anchorDate={new Date('2026-03-01T12:00:00Z')}
      />,
    );
    expect(screen.getByTestId('calendar')).toHaveAttribute('data-view', 'month');
    expect(screen.getByText(/U10 Skills/)).toBeInTheDocument();
  });

  it('shows capacity badges in the week view', async () => {
    render(
      <Calendar
        events={events}
        timezone="America/Toronto"
        anchorDate={new Date('2026-03-09T12:00:00Z')}
      />,
    );
    await userEvent.click(screen.getByRole('tab', { name: 'Week' }));
    expect(screen.getByText('5/10')).toHaveAttribute('aria-label', '5 of 10 spots booked');
    expect(screen.getByText('12/12')).toHaveAttribute('aria-label', '12 of 12 spots booked');
  });

  it('groups events by the venue timezone, not the viewer timezone', () => {
    const lateEvent: CalendarEvent = {
      id: 'late',
      title: 'Late Session',
      startsAt: '2026-03-10T02:00:00Z',
      endsAt: '2026-03-10T03:00:00Z',
    };
    render(
      <Calendar
        events={[lateEvent]}
        timezone="America/Vancouver"
        defaultView="agenda"
        anchorDate={new Date('2026-03-01T12:00:00Z')}
      />,
    );
    expect(screen.getByText('Late Session')).toBeInTheDocument();
  });

  it('switches to the week view', async () => {
    render(
      <Calendar
        events={events}
        timezone="America/Toronto"
        anchorDate={new Date('2026-03-09T12:00:00Z')}
      />,
    );
    await userEvent.click(screen.getByRole('tab', { name: 'Week' }));
    expect(screen.getByTestId('calendar')).toHaveAttribute('data-view', 'week');
  });

  it('switches to the agenda view and shows time ranges', async () => {
    render(
      <Calendar
        events={events}
        timezone="America/Toronto"
        anchorDate={new Date('2026-03-09T12:00:00Z')}
      />,
    );
    await userEvent.click(screen.getByRole('tab', { name: 'Agenda' }));
    const agenda = screen.getByTestId('calendar');
    expect(within(agenda).getByText('U12 Match')).toBeInTheDocument();
  });

  it('notifies view changes', async () => {
    const onViewChange = vi.fn();
    render(<Calendar events={events} timezone="America/Toronto" onViewChange={onViewChange} />);
    await userEvent.click(screen.getByRole('tab', { name: 'Agenda' }));
    expect(onViewChange).toHaveBeenCalledWith('agenda');
  });

  it('invokes onEventClick when an event is clicked (week view)', async () => {
    const onEventClick = vi.fn();
    render(
      <Calendar
        events={events}
        timezone="America/Toronto"
        anchorDate={new Date('2026-03-09T12:00:00Z')}
        onEventClick={onEventClick}
      />,
    );
    await userEvent.click(screen.getByRole('tab', { name: 'Week' }));
    await userEvent.click(screen.getByRole('button', { name: /U10 Skills/ }));
    expect(onEventClick).toHaveBeenCalledWith(expect.objectContaining({ id: 'e1' }));
  });

  it('invokes onEventClick from the agenda view', async () => {
    const onEventClick = vi.fn();
    render(
      <Calendar
        events={events}
        timezone="America/Toronto"
        defaultView="agenda"
        anchorDate={new Date('2026-03-09T12:00:00Z')}
        onEventClick={onEventClick}
      />,
    );
    await userEvent.click(screen.getByRole('button', { name: /U12 Match/ }));
    expect(onEventClick).toHaveBeenCalledWith(expect.objectContaining({ id: 'e2' }));
  });
});
