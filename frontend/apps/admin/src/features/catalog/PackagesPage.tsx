import { useEffect, useState } from 'react';
import { Controller, useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { Plus } from 'lucide-react';
import { applyApiFieldErrors } from '@scb/api-client';
import {
  Badge,
  Button,
  Checkbox,
  ConfirmDialog,
  Drawer,
  EmptyState,
  FormField,
  Input,
  MoneyDisplay,
  MoneyInput,
  Switch,
  Table,
  useToast,
} from '@scb/ui';
import {
  useArchivePackage,
  useCreatePackage,
  useOfferings,
  usePackages,
  useUpdatePackage,
  type PackageRequest,
  type PackageResponse,
} from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';
import { useTenantSettings } from '../shared/useTenantSettings';

const optionalInt = z.preprocess(
  (value) => (value === '' || value === null || Number.isNaN(value) ? null : Number(value)),
  z.number().min(0).nullable(),
);

const schema = z.object({
  name: z.string().min(1, 'Name is required'),
  description: z.string(),
  credit_quantity: z.coerce.number().min(1, 'At least 1 session'),
  price: z.number().min(0),
  validity_days: optionalInt,
  per_household_limit: optionalInt,
  visible_in_portal: z.boolean(),
  taxable: z.boolean(),
  active: z.boolean(),
  offering_ids: z.array(z.string()),
});

type FormValues = z.infer<typeof schema>;

const DEFAULTS: FormValues = {
  name: '',
  description: '',
  credit_quantity: 1,
  price: 0,
  validity_days: 365,
  per_household_limit: null,
  visible_in_portal: true,
  taxable: true,
  active: true,
  offering_ids: [],
};

export function PackagesPage() {
  const query = usePackages();
  const offeringsQuery = useOfferings();
  const create = useCreatePackage();
  const update = useUpdatePackage();
  const archive = useArchivePackage();
  const { toast } = useToast();
  const { currency } = useTenantSettings();

  const [editing, setEditing] = useState<PackageResponse | null>(null);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [pendingArchive, setPendingArchive] = useState<PackageResponse | null>(null);

  const packages = listItems<PackageResponse>(query);
  const offerings = listItems<{ id: string; name: string }>(offeringsQuery);

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
    if (!drawerOpen) return;
    reset(
      editing
        ? {
            name: editing.name,
            description: editing.description ?? '',
            credit_quantity: editing.credit_quantity,
            price: editing.price,
            validity_days: editing.validity_days ?? null,
            per_household_limit: editing.per_household_limit ?? null,
            visible_in_portal: editing.visible_in_portal,
            taxable: editing.taxable ?? true,
            active: editing.active,
            offering_ids: editing.offering_ids ?? [],
          }
        : DEFAULTS,
    );
  }, [drawerOpen, editing, reset]);

  const onSubmit = handleSubmit(async (values) => {
    const payload: PackageRequest = {
      name: values.name,
      description: values.description || null,
      credit_quantity: values.credit_quantity,
      price: values.price,
      validity_days: values.validity_days,
      per_household_limit: values.per_household_limit,
      visible_in_portal: values.visible_in_portal,
      taxable: values.taxable,
      active: values.active,
      offering_ids: values.offering_ids,
    };
    try {
      if (editing) {
        await update.mutateAsync({ id: editing.id, data: payload });
        toast({ title: 'Package updated', variant: 'success' });
      } else {
        await create.mutateAsync({ data: payload });
        toast({ title: 'Package created', variant: 'success' });
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
      toast({ title: 'Package archived', variant: 'success' });
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    } finally {
      setPendingArchive(null);
    }
  };

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title="Packages"
        description="Session bundles customers can buy."
        actions={
          <Button
            onClick={() => {
              setEditing(null);
              setDrawerOpen(true);
            }}
          >
            <Plus className="h-4 w-4" aria-hidden="true" />
            Add package
          </Button>
        }
      />

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {packages.length === 0 ? (
          <EmptyState
            title="No packages yet"
            description="Sell sessions in bundles with expiry rules."
          />
        ) : (
          <Table
            caption="Packages"
            rowKey={(row) => row.id}
            columns={[
              { key: 'name', header: 'Name', cell: (row) => row.name },
              { key: 'credits', header: 'Sessions', cell: (row) => row.credit_quantity },
              {
                key: 'price',
                header: 'Price',
                cell: (row) => <MoneyDisplay amountMinor={row.price} currency={currency} />,
              },
              {
                key: 'validity',
                header: 'Validity',
                cell: (row) => (row.validity_days ? `${row.validity_days} days` : 'No expiry'),
              },
              {
                key: 'portal',
                header: 'Portal',
                cell: (row) => (
                  <Badge variant={row.visible_in_portal ? 'success' : 'outline'}>
                    {row.visible_in_portal ? 'Visible' : 'Hidden'}
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
            data={packages}
          />
        )}
      </QueryState>

      <Drawer
        open={drawerOpen}
        onOpenChange={setDrawerOpen}
        title={editing ? 'Edit package' : 'Add package'}
        footer={
          <>
            <Button variant="outline" onClick={() => setDrawerOpen(false)}>
              Cancel
            </Button>
            <Button onClick={() => void onSubmit()} disabled={create.isPending || update.isPending}>
              Save package
            </Button>
          </>
        }
      >
        <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
          <FormField label="Name" required error={errors.name?.message}>
            <Input {...register('name')} />
          </FormField>
          <FormField label="Description">
            <Input {...register('description')} />
          </FormField>
          <div className="grid gap-4 sm:grid-cols-2">
            <FormField label="Sessions" error={undefined}>
              <Input type="number" {...register('credit_quantity')} />
            </FormField>
            <FormField label="Price">
              <Controller
                control={control}
                name="price"
                render={({ field }) => (
                  <MoneyInput currency={currency} value={field.value} onChange={field.onChange} />
                )}
              />
            </FormField>
            <FormField label="Validity (days)" help="Leave blank for no expiry.">
              <Input type="number" {...register('validity_days')} />
            </FormField>
            <FormField label="Per-household limit">
              <Input type="number" {...register('per_household_limit')} />
            </FormField>
          </div>
          <div className="flex gap-6">
            <Switch
              label="Visible in portal"
              checked={watch('visible_in_portal')}
              onCheckedChange={(checked) => setValue('visible_in_portal', checked)}
            />
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
          <FormField label="Eligible offerings" help="Leave empty to allow any offering.">
            <Controller
              control={control}
              name="offering_ids"
              render={({ field }) => (
                <div className="flex flex-col gap-2">
                  {offerings.map((offering) => (
                    <Checkbox
                      key={offering.id}
                      label={offering.name}
                      checked={field.value.includes(offering.id)}
                      onCheckedChange={(checked) => {
                        field.onChange(
                          checked
                            ? [...field.value, offering.id]
                            : field.value.filter((id) => id !== offering.id),
                        );
                      }}
                    />
                  ))}
                </div>
              )}
            />
          </FormField>
        </form>
      </Drawer>

      <ConfirmDialog
        open={pendingArchive !== null}
        onOpenChange={(open) => !open && setPendingArchive(null)}
        title="Archive package?"
        description="Archived packages can no longer be purchased. Existing sessions are unaffected."
        confirmLabel="Archive"
        destructive
        loading={archive.isPending}
        onConfirm={() => void confirmArchive()}
      />
    </div>
  );
}
