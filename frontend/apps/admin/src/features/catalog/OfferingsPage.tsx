import { useEffect, useState } from 'react';
import {
  Controller,
  useForm,
  type Control,
  type UseFormRegister,
  type UseFormSetValue,
  type UseFormWatch,
} from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { ArrowDown, ArrowUp, Plus } from 'lucide-react';
import { applyApiFieldErrors } from '@scb/api-client';
import {
  Badge,
  Button,
  ConfirmDialog,
  Drawer,
  EmptyState,
  FormField,
  Input,
  MoneyInput,
  Switch,
  Table,
  useToast,
} from '@scb/ui';
import {
  useArchiveOffering,
  useCreateOffering,
  useOfferings,
  useReorderOfferings,
  useUpdateOffering,
  type OfferingRequest,
  type OfferingResponse,
} from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';
import { useTenantSettings } from '../shared/useTenantSettings';

const schema = z.object({
  name: z.string().min(1, 'Name is required'),
  min_age: z.coerce.number().min(0).max(120),
  max_age: z.coerce.number().min(0).max(120),
  duration_minutes: z.coerce.number().min(5, 'At least 5 minutes'),
  bookable_from_days_ahead: z.coerce.number().min(0),
  bookable_until_minutes_before: z.coerce.number().min(0),
  taxable: z.boolean(),
  active: z.boolean(),
  description: z.string(),
  public_enabled: z.boolean(),
  public_max_players: z.coerce.number().min(1),
  public_players_per_coach: z.coerce.number().min(1),
  public_price_tiers: z.record(
    z.string(),
    z.object({ price: z.number().nullable(), credit_cost: z.coerce.number().min(0) }),
  ),
  private_enabled: z.boolean(),
  private_max_players: z.coerce.number().min(1),
  private_players_per_coach: z.coerce.number().min(1),
  private_price_tiers: z.record(
    z.string(),
    z.object({ price: z.number().nullable(), credit_cost: z.coerce.number().min(0) }),
  ),
  allow_invite_reservations: z.boolean(),
  invite_hold_hours: z.coerce.number().min(1),
  allow_private_conversion: z.boolean(),
  allow_private_requests: z.boolean(),
});

type FormValues = z.infer<typeof schema>;

const DEFAULTS: FormValues = {
  name: '',
  min_age: 5,
  max_age: 18,
  duration_minutes: 60,
  bookable_from_days_ahead: 60,
  bookable_until_minutes_before: 60,
  taxable: true,
  active: true,
  description: '',
  public_enabled: true,
  public_max_players: 2,
  public_players_per_coach: 2,
  public_price_tiers: {
    '1': { price: null, credit_cost: 1 },
    '2': { price: null, credit_cost: 1 },
  },
  private_enabled: false,
  private_max_players: 4,
  private_players_per_coach: 4,
  private_price_tiers: {
    '1': { price: null, credit_cost: 1 },
    '2': { price: null, credit_cost: 1 },
    '3': { price: null, credit_cost: 1 },
    '4': { price: null, credit_cost: 1 },
  },
  allow_invite_reservations: false,
  invite_hold_hours: 48,
  allow_private_conversion: false,
  allow_private_requests: false,
};

function normalizeTiers(
  value: unknown,
): Record<string, { price: number | null; credit_cost: number }> {
  if (!value || typeof value !== 'object') return {};
  return Object.fromEntries(
    Object.entries(value).flatMap(([size, tier]) => {
      if (!tier || typeof tier !== 'object') return [];
      const row = tier as { price?: unknown; credit_cost?: unknown };
      const price = typeof row.price === 'number' ? row.price : null;
      const creditCost = typeof row.credit_cost === 'number' ? row.credit_cost : 0;
      return [[size, { price, credit_cost: creditCost }]];
    }),
  );
}

function tiersThroughMax(
  tiers: Record<string, { price: number | null; credit_cost: number }>,
  maxPlayers: number,
) {
  return Object.fromEntries(
    Array.from({ length: maxPlayers }, (_, index) => {
      const size = String(index + 1);
      return [size, tiers[size] ?? { price: null, credit_cost: 0 }];
    }),
  );
}

export function OfferingsPage() {
  const query = useOfferings();
  const create = useCreateOffering();
  const update = useUpdateOffering();
  const archive = useArchiveOffering();
  const reorder = useReorderOfferings();
  const { toast } = useToast();
  const { currency } = useTenantSettings();

  const [editing, setEditing] = useState<OfferingResponse | null>(null);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [pendingArchive, setPendingArchive] = useState<OfferingResponse | null>(null);

  const offerings = listItems<OfferingResponse>(query);
  const { register, control, handleSubmit, reset, setError, watch, setValue, formState } =
    useForm<FormValues>({ resolver: zodResolver(schema), defaultValues: DEFAULTS });
  const { errors } = formState;

  useEffect(() => {
    if (!drawerOpen) return;
    reset(
      editing
        ? {
            name: editing.name,
            min_age: editing.min_age ?? 0,
            max_age: editing.max_age ?? 120,
            duration_minutes: editing.duration_minutes,
            bookable_from_days_ahead: editing.bookable_from_days_ahead ?? 60,
            bookable_until_minutes_before: editing.bookable_until_minutes_before ?? 0,
            taxable: editing.taxable ?? true,
            active: editing.active,
            description: editing.description ?? '',
            public_enabled: editing.public_enabled ?? editing.format !== 'private',
            public_max_players: editing.public_max_players ?? editing.default_capacity ?? 1,
            public_players_per_coach:
              editing.public_players_per_coach ?? editing.default_capacity ?? 1,
            public_price_tiers: normalizeTiers(editing.public_price_tiers),
            private_enabled: editing.private_enabled ?? editing.format === 'private',
            private_max_players: editing.private_max_players ?? editing.default_capacity ?? 1,
            private_players_per_coach:
              editing.private_players_per_coach ?? editing.default_capacity ?? 1,
            private_price_tiers: normalizeTiers(editing.private_price_tiers),
            allow_invite_reservations: editing.allow_invite_reservations ?? false,
            invite_hold_hours: editing.invite_hold_hours ?? 48,
            allow_private_conversion: editing.allow_private_conversion ?? false,
            allow_private_requests: editing.allow_private_requests ?? false,
          }
        : DEFAULTS,
    );
  }, [drawerOpen, editing, reset]);

  const onSubmit = handleSubmit(async (values) => {
    const primarySize = values.public_enabled
      ? values.public_max_players
      : values.private_max_players;
    const primaryTier = values.public_enabled
      ? values.public_price_tiers[String(primarySize)]
      : values.private_price_tiers[String(primarySize)];
    const payload: OfferingRequest = {
      ...values,
      public_price_tiers: tiersThroughMax(values.public_price_tiers, values.public_max_players),
      private_price_tiers: tiersThroughMax(values.private_price_tiers, values.private_max_players),
      format: values.public_enabled
        ? values.public_max_players === 2
          ? 'semi_private'
          : 'group'
        : 'private',
      default_capacity: primarySize,
      credit_cost: primaryTier?.credit_cost ?? 0,
      drop_in_price: primaryTier?.price ?? null,
      description: values.description || null,
      min_age: values.min_age,
      max_age: values.max_age,
    };
    try {
      if (editing) {
        await update.mutateAsync({ id: editing.id, data: payload });
        toast({ title: 'Offering updated', variant: 'success' });
      } else {
        await create.mutateAsync({ data: payload });
        toast({ title: 'Offering created', variant: 'success' });
      }
      setDrawerOpen(false);
    } catch (error) {
      const applied = applyApiFieldErrors(error, { setError, fallbackField: 'name' });
      if (!applied.handled) toast({ title: errorMessage(error), variant: 'danger' });
    }
  });

  const reorderBy = async (index: number, delta: number) => {
    const next = [...offerings];
    const target = index + delta;
    if (target < 0 || target >= next.length) return;
    [next[index], next[target]] = [next[target], next[index]];
    try {
      await reorder.mutateAsync({ data: { ids: next.map((item) => item.id) } });
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    }
  };

  const confirmArchive = async () => {
    if (!pendingArchive) return;
    try {
      await archive.mutateAsync({ id: pendingArchive.id });
      toast({ title: 'Offering archived', variant: 'success' });
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    } finally {
      setPendingArchive(null);
    }
  };

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title="Offerings"
        description="The types of sessions you sell."
        actions={
          <Button
            onClick={() => {
              setEditing(null);
              setDrawerOpen(true);
            }}
          >
            <Plus className="h-4 w-4" aria-hidden="true" />
            Add offering
          </Button>
        }
      />

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {offerings.length === 0 ? (
          <EmptyState
            title="No offerings yet"
            description="Create an offering such as 'Private 1:1' or 'Group clinic'."
          />
        ) : (
          <Table
            caption="Offerings"
            rowKey={(row) => row.id}
            columns={[
              { key: 'name', header: 'Name', cell: (row) => row.name },
              {
                key: 'format',
                header: 'Booking modes',
                cell: (row) => (
                  <div className="flex gap-1">
                    {row.public_enabled ? <Badge variant="secondary">Public</Badge> : null}
                    {row.private_enabled ? <Badge variant="secondary">Private</Badge> : null}
                  </div>
                ),
              },
              {
                key: 'age',
                header: 'Ages',
                cell: (row) => `${row.min_age ?? '—'}–${row.max_age ?? '—'}`,
              },
              { key: 'duration', header: 'Duration', cell: (row) => `${row.duration_minutes} min` },
              { key: 'capacity', header: 'Capacity', cell: (row) => row.default_capacity ?? 1 },
              { key: 'credits', header: 'Sessions', cell: (row) => row.credit_cost ?? 0 },
              {
                key: 'order',
                header: 'Order',
                cell: (row) => {
                  const index = offerings.indexOf(row);
                  return (
                    <div className="flex gap-1">
                      <Button
                        variant="ghost"
                        size="sm"
                        aria-label={`Move ${row.name} up`}
                        onClick={() => void reorderBy(index, -1)}
                      >
                        <ArrowUp className="h-3.5 w-3.5" />
                      </Button>
                      <Button
                        variant="ghost"
                        size="sm"
                        aria-label={`Move ${row.name} down`}
                        onClick={() => void reorderBy(index, 1)}
                      >
                        <ArrowDown className="h-3.5 w-3.5" />
                      </Button>
                    </div>
                  );
                },
              },
              {
                key: 'actions',
                header: '',
                align: 'right',
                cell: (row) => (
                  <div className="flex justify-end gap-1">
                    <Button
                      variant="ghost"
                      size="sm"
                      onClick={() => {
                        setEditing(row);
                        setDrawerOpen(true);
                      }}
                    >
                      Edit
                    </Button>
                    <Button
                      variant="ghost"
                      size="sm"
                      disabled={!row.active}
                      onClick={() => setPendingArchive(row)}
                    >
                      Archive
                    </Button>
                  </div>
                ),
              },
            ]}
            data={offerings}
          />
        )}
      </QueryState>

      <Drawer
        open={drawerOpen}
        onOpenChange={setDrawerOpen}
        title={editing ? 'Edit offering' : 'Add offering'}
        footer={
          <>
            <Button variant="outline" onClick={() => setDrawerOpen(false)}>
              Cancel
            </Button>
            <Button onClick={() => void onSubmit()} disabled={create.isPending || update.isPending}>
              Save offering
            </Button>
          </>
        }
      >
        <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
          <FormField label="Name" required error={errors.name?.message}>
            <Input {...register('name')} />
          </FormField>
          <div className="grid gap-4 sm:grid-cols-2">
            <FormField label="Minimum age">
              <Input type="number" {...register('min_age')} />
            </FormField>
            <FormField label="Maximum age">
              <Input type="number" {...register('max_age')} />
            </FormField>
            <FormField label="Duration (minutes)" error={errors.duration_minutes?.message}>
              <Input type="number" {...register('duration_minutes')} />
            </FormField>
            <FormField label="Bookable from (days ahead)">
              <Input type="number" {...register('bookable_from_days_ahead')} />
            </FormField>
            <FormField label="Bookable until (minutes before)">
              <Input type="number" {...register('bookable_until_minutes_before')} />
            </FormField>
          </div>
          <FormField label="Description">
            <Input {...register('description')} />
          </FormField>
          <BookingModeFields
            mode="public"
            label="Public bookings"
            control={control}
            register={register}
            watch={watch}
            setValue={setValue}
            currency={currency}
          />
          <BookingModeFields
            mode="private"
            label="Private bookings"
            control={control}
            register={register}
            watch={watch}
            setValue={setValue}
            currency={currency}
          />
          <div className="rounded-md border border-border p-3 flex flex-col gap-3">
            <Switch
              label="Allow players to reserve spaces for invitees"
              checked={watch('allow_invite_reservations')}
              onCheckedChange={(checked) => setValue('allow_invite_reservations', checked)}
            />
            {watch('allow_invite_reservations') ? (
              <FormField label="Maximum invite reservation (hours)">
                <Input type="number" {...register('invite_hold_hours')} />
              </FormField>
            ) : null}
            <Switch
              label="Allow players to make a published session private"
              checked={watch('allow_private_conversion')}
              onCheckedChange={(checked) => setValue('allow_private_conversion', checked)}
            />
            <Switch
              label="Allow players to request a new private session"
              checked={watch('allow_private_requests')}
              onCheckedChange={(checked) => setValue('allow_private_requests', checked)}
            />
          </div>
          <div className="flex gap-6">
            <Switch
              label="Taxable"
              checked={watch('taxable')}
              onCheckedChange={(checked) => setValue('taxable', checked)}
            />
            <Switch
              label="Active"
              checked={watch('active')}
              onCheckedChange={(checked) => setValue('active', checked)}
            />
          </div>
        </form>
      </Drawer>

      <ConfirmDialog
        open={pendingArchive !== null}
        onOpenChange={(open) => !open && setPendingArchive(null)}
        title="Archive offering?"
        description="Archived offerings remain on past sessions but cannot be booked again."
        confirmLabel="Archive"
        destructive
        loading={archive.isPending}
        onConfirm={() => void confirmArchive()}
      />
    </div>
  );
}

type Mode = 'public' | 'private';

function BookingModeFields({
  mode,
  label,
  control,
  register,
  watch,
  setValue,
  currency,
}: {
  mode: Mode;
  label: string;
  control: Control<FormValues>;
  register: UseFormRegister<FormValues>;
  watch: UseFormWatch<FormValues>;
  setValue: UseFormSetValue<FormValues>;
  currency: string;
}) {
  const enabled = watch(`${mode}_enabled`) as boolean;
  const maxPlayers = Number(watch(`${mode}_max_players`) || 1);

  return (
    <fieldset className="rounded-md border border-border p-3 flex flex-col gap-3">
      <legend className="px-1 text-sm font-medium">{label}</legend>
      <Switch
        label={`Enable ${mode} bookings`}
        checked={enabled}
        onCheckedChange={(checked) => setValue(`${mode}_enabled`, checked)}
      />
      {enabled ? (
        <>
          <div className="grid gap-4 sm:grid-cols-2">
            <FormField label="Maximum players">
              <Input type="number" {...register(`${mode}_max_players`)} />
            </FormField>
            <FormField label="Players per coach">
              <Input type="number" {...register(`${mode}_players_per_coach`)} />
            </FormField>
          </div>
          <div className="flex flex-col gap-2">
            <p className="text-sm font-medium">Per-player price tiers</p>
            {Array.from({ length: Math.max(1, maxPlayers) }, (_, index) => index + 1).map(
              (players) => (
                <div key={players} className="grid grid-cols-[5rem_1fr_1fr] items-end gap-2">
                  <span className="pb-2 text-sm text-muted-foreground">
                    {players} player{players === 1 ? '' : 's'}
                  </span>
                  <FormField label="Price each">
                    <Controller
                      control={control}
                      name={`${mode}_price_tiers.${players}.price`}
                      defaultValue={null}
                      render={({ field }) => (
                        <MoneyInput
                          currency={currency}
                          value={field.value}
                          onChange={field.onChange}
                        />
                      )}
                    />
                  </FormField>
                  <FormField label="Credits each">
                    <Input
                      type="number"
                      defaultValue={1}
                      {...register(`${mode}_price_tiers.${players}.credit_cost`)}
                    />
                  </FormField>
                </div>
              ),
            )}
          </div>
        </>
      ) : null}
    </fieldset>
  );
}
