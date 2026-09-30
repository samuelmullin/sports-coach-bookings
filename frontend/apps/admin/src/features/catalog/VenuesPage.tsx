import { useEffect, useState } from 'react';
import { Controller, useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { Plus } from 'lucide-react';
import { applyApiFieldErrors } from '@scb/api-client';
import {
  Badge,
  Button,
  Drawer,
  EmptyState,
  FormField,
  Input,
  Switch,
  Table,
  useToast,
} from '@scb/ui';
import {
  useArchiveVenue,
  useCreateVenue,
  useUpdateVenue,
  useVenues,
  type VenueRequest,
  type VenueResponse,
} from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';
import { TIMEZONES } from '../settings/constants';
import { ConfirmDialog } from '@scb/ui';
import { Select } from '@scb/ui';

const schema = z.object({
  name: z.string().min(1, 'Name is required'),
  timezone: z.string().min(1, 'Timezone is required'),
  address_line1: z.string(),
  city: z.string(),
  province: z.string(),
  postal_code: z.string(),
  notes: z.string(),
  active: z.boolean(),
});

type FormValues = z.infer<typeof schema>;

const DEFAULTS: FormValues = {
  name: '',
  timezone: 'America/Toronto',
  address_line1: '',
  city: '',
  province: '',
  postal_code: '',
  notes: '',
  active: true,
};

function toValues(venue: VenueResponse): FormValues {
  return {
    name: venue.name,
    timezone: venue.timezone,
    address_line1: venue.address_line1 ?? '',
    city: venue.city ?? '',
    province: venue.province ?? '',
    postal_code: venue.postal_code ?? '',
    notes: venue.notes ?? '',
    active: venue.active,
  };
}

export function VenuesPage() {
  const query = useVenues();
  const create = useCreateVenue();
  const update = useUpdateVenue();
  const archive = useArchiveVenue();
  const { toast } = useToast();

  const [editing, setEditing] = useState<VenueResponse | null>(null);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [pendingArchive, setPendingArchive] = useState<VenueResponse | null>(null);

  const venues = listItems<VenueResponse>(query);
  const {
    register,
    control,
    handleSubmit,
    reset,
    setError,
    watch,
    setValue,
    formState: { errors },
  } = useForm<FormValues>({ resolver: zodResolver(schema), defaultValues: DEFAULTS });

  useEffect(() => {
    if (drawerOpen) reset(editing ? toValues(editing) : DEFAULTS);
  }, [drawerOpen, editing, reset]);

  const openCreate = () => {
    setEditing(null);
    setDrawerOpen(true);
  };

  const onSubmit = handleSubmit(async (values) => {
    const payload: VenueRequest = {
      ...values,
      address_line1: values.address_line1 || null,
      city: values.city || null,
      province: values.province || null,
      postal_code: values.postal_code || null,
      notes: values.notes || null,
    };
    try {
      if (editing) {
        await update.mutateAsync({ id: editing.id, data: payload });
        toast({ title: 'Venue updated', variant: 'success' });
      } else {
        await create.mutateAsync({ data: payload });
        toast({ title: 'Venue created', variant: 'success' });
      }
      setDrawerOpen(false);
    } catch (error) {
      const applied = applyApiFieldErrors(error, { setError, fallbackField: 'name' });
      if (!applied.handled) toast({ title: errorMessage(error), variant: 'danger' });
    }
  });

  const confirmArchive = async () => {
    if (!pendingArchive) return;
    try {
      await archive.mutateAsync({ id: pendingArchive.id });
      toast({ title: 'Venue archived', variant: 'success' });
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    } finally {
      setPendingArchive(null);
    }
  };

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title="Venues"
        description="Where your sessions happen. Times are shown in each venue's timezone."
        actions={
          <Button onClick={openCreate}>
            <Plus className="h-4 w-4" aria-hidden="true" />
            Add venue
          </Button>
        }
      />

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {venues.length === 0 ? (
          <EmptyState
            title="No venues yet"
            description="Add your first venue to start scheduling sessions."
            action={<Button onClick={openCreate}>Add venue</Button>}
          />
        ) : (
          <Table
            caption="Venues"
            rowKey={(row) => row.id}
            columns={[
              { key: 'name', header: 'Name', cell: (row) => row.name },
              {
                key: 'address',
                header: 'Address',
                cell: (row) =>
                  [row.address_line1, row.city, row.province].filter(Boolean).join(', ') || '—',
              },
              { key: 'timezone', header: 'Timezone', cell: (row) => row.timezone },
              {
                key: 'status',
                header: 'Status',
                cell: (row) => (
                  <Badge variant={row.active ? 'success' : 'outline'}>
                    {row.active ? 'Active' : 'Archived'}
                  </Badge>
                ),
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
            data={venues}
          />
        )}
      </QueryState>

      <Drawer
        open={drawerOpen}
        onOpenChange={setDrawerOpen}
        title={editing ? 'Edit venue' : 'Add venue'}
        footer={
          <>
            <Button variant="outline" onClick={() => setDrawerOpen(false)}>
              Cancel
            </Button>
            <Button onClick={() => void onSubmit()} disabled={create.isPending || update.isPending}>
              Save venue
            </Button>
          </>
        }
      >
        <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
          <FormField label="Name" required error={errors.name?.message}>
            <Input {...register('name')} />
          </FormField>
          <FormField label="Timezone" required error={errors.timezone?.message}>
            <Controller
              control={control}
              name="timezone"
              render={({ field }) => (
                <Select
                  aria-label="Timezone"
                  value={field.value}
                  onValueChange={field.onChange}
                  options={TIMEZONES.map((zone) => ({ value: zone, label: zone }))}
                />
              )}
            />
          </FormField>
          <FormField label="Address line 1">
            <Input {...register('address_line1')} />
          </FormField>
          <div className="grid gap-4 sm:grid-cols-3">
            <FormField label="City">
              <Input {...register('city')} />
            </FormField>
            <FormField label="Province / State">
              <Input {...register('province')} />
            </FormField>
            <FormField label="Postal code">
              <Input {...register('postal_code')} />
            </FormField>
          </div>
          <FormField label="Notes">
            <Input {...register('notes')} />
          </FormField>
          <Switch
            label="Active"
            checked={watch('active')}
            onCheckedChange={(checked) => setValue('active', checked)}
          />
        </form>
      </Drawer>

      <ConfirmDialog
        open={pendingArchive !== null}
        onOpenChange={(open) => !open && setPendingArchive(null)}
        title="Archive venue?"
        description="Archived venues cannot be used for new sessions. Existing sessions are unaffected."
        confirmLabel="Archive"
        destructive
        loading={archive.isPending}
        onConfirm={() => void confirmArchive()}
      />
    </div>
  );
}
