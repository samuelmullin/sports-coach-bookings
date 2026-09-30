import { useEffect, useState } from 'react';
import { Controller, useForm } from 'react-hook-form';
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
  Select,
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
  format: z.enum(['private', 'semi_private', 'group']),
  min_age: z.coerce.number().min(0).max(120),
  max_age: z.coerce.number().min(0).max(120),
  duration_minutes: z.coerce.number().min(5, 'At least 5 minutes'),
  default_capacity: z.coerce.number().min(1, 'At least 1'),
  credit_cost: z.coerce.number().min(0),
  drop_in_price: z.number().nullable(),
  bookable_from_days_ahead: z.coerce.number().min(0),
  bookable_until_minutes_before: z.coerce.number().min(0),
  taxable: z.boolean(),
  active: z.boolean(),
  description: z.string(),
});

type FormValues = z.infer<typeof schema>;

const DEFAULTS: FormValues = {
  name: '',
  format: 'group',
  min_age: 5,
  max_age: 18,
  duration_minutes: 60,
  default_capacity: 1,
  credit_cost: 1,
  drop_in_price: null,
  bookable_from_days_ahead: 60,
  bookable_until_minutes_before: 60,
  taxable: true,
  active: true,
  description: '',
};

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
            format: editing.format,
            min_age: editing.min_age ?? 0,
            max_age: editing.max_age ?? 120,
            duration_minutes: editing.duration_minutes,
            default_capacity: editing.default_capacity ?? 1,
            credit_cost: editing.credit_cost ?? 0,
            drop_in_price: editing.drop_in_price ?? null,
            bookable_from_days_ahead: editing.bookable_from_days_ahead ?? 60,
            bookable_until_minutes_before: editing.bookable_until_minutes_before ?? 0,
            taxable: editing.taxable ?? true,
            active: editing.active,
            description: editing.description ?? '',
          }
        : DEFAULTS,
    );
  }, [drawerOpen, editing, reset]);

  const onSubmit = handleSubmit(async (values) => {
    const payload: OfferingRequest = {
      ...values,
      description: values.description || null,
      drop_in_price: values.drop_in_price,
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
                header: 'Format',
                cell: (row) => <Badge variant="secondary">{row.format.replace('_', ' ')}</Badge>,
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
          <Controller
            control={control}
            name="format"
            render={({ field }) => (
              <FormField label="Format" required>
                <Select
                  aria-label="Format"
                  value={field.value}
                  onValueChange={field.onChange}
                  options={[
                    { value: 'private', label: 'Private' },
                    { value: 'semi_private', label: 'Semi-private' },
                    { value: 'group', label: 'Group' },
                  ]}
                />
              </FormField>
            )}
          />
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
            <FormField label="Default capacity" error={errors.default_capacity?.message}>
              <Input type="number" {...register('default_capacity')} />
            </FormField>
            <FormField label="Session cost">
              <Input type="number" {...register('credit_cost')} />
            </FormField>
            <FormField label="Drop-in price">
              <Controller
                control={control}
                name="drop_in_price"
                render={({ field }) => (
                  <MoneyInput currency={currency} value={field.value} onChange={field.onChange} />
                )}
              />
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
