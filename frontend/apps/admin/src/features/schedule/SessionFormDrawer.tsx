import { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { applyApiFieldErrors } from '@scb/api-client';
import {
  Button,
  Checkbox,
  Drawer,
  FormField,
  Input,
  Select,
  Switch,
  TimePicker,
  zonedDateToUtc,
} from '@scb/ui';
import {
  useCreateSession,
  useCreateSessionSeries,
  useOfferings,
  useTeam,
  useVenues,
} from '../../api/endpoints';
import { listItems, errorMessage, responseData } from '../shared/api-utils';
import { useTenantSettings } from '../shared/useTenantSettings';
import { useToast } from '@scb/ui';

const WEEKDAYS = [
  { value: 1, label: 'Mon' },
  { value: 2, label: 'Tue' },
  { value: 3, label: 'Wed' },
  { value: 4, label: 'Thu' },
  { value: 5, label: 'Fri' },
  { value: 6, label: 'Sat' },
  { value: 7, label: 'Sun' },
];

const schema = z.object({
  mode: z.enum(['single', 'series']),
  offering_id: z.string().min(1, 'Choose an offering'),
  venue_id: z.string().min(1, 'Choose a venue'),
  date: z.string().min(1, 'Choose a date'),
  start_time: z.string().min(1, 'Choose a start time'),
  duration_minutes: z.coerce.number().min(5),
  capacity: z.coerce.number().min(1),
  coach_ids: z.array(z.string()),
  visibility: z.enum(['public', 'hidden']),
  show_coaches: z.boolean(),
  title_override: z.string(),
  notes_public: z.string(),
  weekdays: z.array(z.number()),
  ends_on: z.string(),
});

type FormValues = z.infer<typeof schema>;

const DEFAULTS: FormValues = {
  mode: 'single',
  offering_id: '',
  venue_id: '',
  date: '',
  start_time: '18:00',
  duration_minutes: 60,
  capacity: 1,
  coach_ids: [],
  visibility: 'public',
  show_coaches: true,
  title_override: '',
  notes_public: '',
  weekdays: [],
  ends_on: '',
};

interface CreateResult {
  warnings?: { type?: string; message?: string }[];
}

export function SessionFormDrawer({
  open,
  onOpenChange,
  onCreated,
  defaultDate,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  onCreated?: () => void;
  defaultDate?: string;
}) {
  const createSession = useCreateSession();
  const createSeries = useCreateSessionSeries();
  const offerings = listItems<{
    id: string;
    name: string;
    duration_minutes: number;
    default_capacity: number;
  }>(useOfferings());
  const venues = listItems<{ id: string; name: string; timezone: string }>(useVenues());
  const team = listItems<{
    id?: string;
    display_name?: string | null;
    role?: string;
    staff_user?: { email?: string };
  }>(useTeam());
  const { timezone } = useTenantSettings();
  const { toast } = useToast();
  const [warnings, setWarnings] = useState<CreateResult['warnings']>([]);

  const {
    register,
    handleSubmit,
    reset,
    setError,
    watch,
    setValue,
    formState: { errors },
  } = useForm<FormValues>({ resolver: zodResolver(schema), defaultValues: DEFAULTS });
  const mode = watch('mode');
  const offeringId = watch('offering_id');
  const venueId = watch('venue_id');

  useEffect(() => {
    if (open) {
      reset({ ...DEFAULTS, date: defaultDate ?? new Date().toISOString().slice(0, 10) });
      setWarnings([]);
    }
  }, [open, defaultDate, reset]);

  useEffect(() => {
    const offering = offerings.find((item) => item.id === offeringId);
    if (offering) {
      setValue('duration_minutes', offering.duration_minutes);
      setValue('capacity', offering.default_capacity || 1);
    }
  }, [offeringId, offerings, setValue]);

  const zone = venues.find((venue) => venue.id === venueId)?.timezone ?? timezone;

  const onSubmit = handleSubmit(async (values) => {
    const startsAt = zonedDateToUtc(
      new Date(`${values.date}T${values.start_time}:00`),
      zone,
    ).toISOString();
    try {
      if (values.mode === 'single') {
        const endsAt = zonedDateToUtc(
          new Date(
            new Date(`${values.date}T${values.start_time}:00`).getTime() +
              values.duration_minutes * 60_000,
          ),
          zone,
        ).toISOString();
        const result = await createSession.mutateAsync({
          data: {
            offering_id: values.offering_id,
            venue_id: values.venue_id,
            starts_at: startsAt,
            ends_at: endsAt,
            capacity: values.capacity,
            coach_ids: values.coach_ids,
            visibility: values.visibility,
            show_coaches: values.show_coaches,
            title_override: values.title_override || null,
            notes_public: values.notes_public || null,
          },
        });
        setWarnings(responseData<CreateResult>(result)?.warnings ?? []);
        toast({ title: 'Session created', variant: 'success' });
      } else {
        const result = await createSeries.mutateAsync({
          data: {
            offering_id: values.offering_id,
            venue_id: values.venue_id,
            starts_on: values.date,
            start_time_local: values.start_time,
            duration_minutes: values.duration_minutes,
            capacity: values.capacity,
            coach_ids: values.coach_ids,
            visibility: values.visibility,
            show_coaches: values.show_coaches,
            title_override: values.title_override || null,
            notes_public: values.notes_public || null,
            weekdays: values.weekdays,
            ends_on: values.ends_on || null,
            timezone: zone,
          },
        });
        setWarnings(responseData<CreateResult>(result)?.warnings ?? []);
        toast({ title: 'Series created', variant: 'success' });
      }
      onCreated?.();
      onOpenChange(false);
    } catch (error) {
      const applied = applyApiFieldErrors(error, {
        setError,
        mappedFields: { starts_at: 'date', ends_at: 'date' },
        fallbackField: 'date',
      });
      if (!applied.handled) toast({ title: errorMessage(error), variant: 'danger' });
    }
  });

  return (
    <Drawer
      open={open}
      onOpenChange={onOpenChange}
      title="New session"
      footer={
        <>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button
            onClick={() => void onSubmit()}
            disabled={createSession.isPending || createSeries.isPending}
          >
            {mode === 'series' ? 'Create series' : 'Create session'}
          </Button>
        </>
      }
    >
      <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
        <div className="flex gap-4">
          <label className="flex items-center gap-2 text-sm">
            <input
              type="radio"
              value="single"
              checked={mode === 'single'}
              onChange={() => setValue('mode', 'single')}
            />
            Single session
          </label>
          <label className="flex items-center gap-2 text-sm">
            <input
              type="radio"
              value="series"
              checked={mode === 'series'}
              onChange={() => setValue('mode', 'series')}
            />
            Recurring series
          </label>
        </div>

        <FormField label="Offering" required error={undefined}>
          <Select
            aria-label="Offering"
            value={offeringId}
            onValueChange={(value) => setValue('offering_id', value)}
            options={offerings.map((offering) => ({ value: offering.id, label: offering.name }))}
          />
        </FormField>
        <FormField label="Venue" required>
          <Select
            aria-label="Venue"
            value={venueId}
            onValueChange={(value) => setValue('venue_id', value)}
            options={venues.map((venue) => ({
              value: venue.id,
              label: `${venue.name} (${venue.timezone})`,
            }))}
          />
        </FormField>

        <div className="grid gap-4 sm:grid-cols-2">
          <FormField
            label={mode === 'series' ? 'First date' : 'Date'}
            required
            error={errors.date?.message}
          >
            <Input type="date" {...register('date')} />
          </FormField>
          <FormField label={`Start time (${zone})`} required>
            <TimePicker {...register('start_time')} />
          </FormField>
          <FormField label="Duration (minutes)">
            <Input type="number" {...register('duration_minutes')} />
          </FormField>
          <FormField label="Capacity">
            <Input type="number" {...register('capacity')} />
          </FormField>
        </div>

        {mode === 'series' ? (
          <div className="flex flex-col gap-3 rounded-md border border-border p-3">
            <span className="text-sm font-medium">Repeat on</span>
            <div className="flex flex-wrap gap-3">
              {WEEKDAYS.map((day) => (
                <Checkbox
                  key={day.value}
                  label={day.label}
                  checked={watch('weekdays').includes(day.value)}
                  onCheckedChange={(checked) =>
                    setValue(
                      'weekdays',
                      checked
                        ? [...watch('weekdays'), day.value].sort()
                        : watch('weekdays').filter((value) => value !== day.value),
                    )
                  }
                />
              ))}
            </div>
            <FormField label="Ends on">
              <Input type="date" {...register('ends_on')} />
            </FormField>
          </div>
        ) : null}

        <FormField label="Coaches">
          <div className="flex flex-col gap-2">
            {team.map((member) => (
              <Checkbox
                key={member.id}
                label={member.display_name || member.staff_user?.email || 'Member'}
                checked={watch('coach_ids').includes(member.id ?? '')}
                onCheckedChange={(checked) =>
                  setValue(
                    'coach_ids',
                    checked
                      ? [...watch('coach_ids'), member.id ?? '']
                      : watch('coach_ids').filter((id) => id !== member.id),
                  )
                }
              />
            ))}
          </div>
        </FormField>

        <FormField label="Title override">
          <Input {...register('title_override')} />
        </FormField>
        <FormField label="Public notes">
          <Input {...register('notes_public')} />
        </FormField>
        <Switch
          label="Published (visible in portal)"
          checked={watch('visibility') === 'public'}
          onCheckedChange={(checked) => setValue('visibility', checked ? 'public' : 'hidden')}
        />
        <Switch
          label="Show coach names to customers"
          checked={watch('show_coaches')}
          onCheckedChange={(checked) => setValue('show_coaches', checked)}
        />

        {warnings && warnings.length > 0 ? (
          <ul className="flex flex-col gap-2" data-testid="session-warnings">
            {warnings.map((warning, index) => (
              <li key={index} className="rounded-md bg-amber-50 p-2 text-xs text-amber-900">
                {warning.type ? `${warning.type}: ` : ''}
                {warning.message ?? 'Potential conflict'}
              </li>
            ))}
          </ul>
        ) : null}
      </form>
    </Drawer>
  );
}
