import { useEffect, useState } from 'react';
import { Controller, useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { Plus } from 'lucide-react';
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
  useArchiveDiscount,
  useCreateDiscount,
  useDiscounts,
  useUpdateDiscount,
  type DiscountRequest,
  type DiscountResponse,
} from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';
import { useTenantSettings } from '../shared/useTenantSettings';

const APPLIES_TO = [
  { value: 'all', label: 'Everything' },
  { value: 'packages', label: 'Packages' },
  { value: 'drop_ins', label: 'Drop-ins' },
  { value: 'products', label: 'Products' },
] as const;

const schema = z.object({
  code: z.string(),
  kind: z.enum(['percent', 'fixed']),
  value: z.number().min(0),
  applies_to: z.enum(['all', 'packages', 'drop_ins', 'products']),
  min_subtotal: z.number().nullable(),
  max_redemptions: z.coerce.number().min(0).nullable(),
  per_household_limit: z.coerce.number().min(0).nullable(),
  starts_at: z.string(),
  ends_at: z.string(),
  active: z.boolean(),
});

type FormValues = z.infer<typeof schema>;

const DEFAULTS: FormValues = {
  code: '',
  kind: 'percent',
  value: 10,
  applies_to: 'all',
  min_subtotal: null,
  max_redemptions: null,
  per_household_limit: null,
  starts_at: '',
  ends_at: '',
  active: true,
};

export function DiscountsPage() {
  const query = useDiscounts();
  const create = useCreateDiscount();
  const update = useUpdateDiscount();
  const archive = useArchiveDiscount();
  const { toast } = useToast();
  const { currency } = useTenantSettings();

  const [editing, setEditing] = useState<DiscountResponse | null>(null);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [pendingArchive, setPendingArchive] = useState<DiscountResponse | null>(null);

  const discounts = listItems<DiscountResponse>(query);
  const { register, control, handleSubmit, reset, setError, watch, setValue } = useForm<FormValues>(
    { resolver: zodResolver(schema), defaultValues: DEFAULTS },
  );
  const kind = watch('kind');

  useEffect(() => {
    if (!drawerOpen) return;
    reset(
      editing
        ? {
            code: editing.code ?? '',
            kind: editing.kind,
            value: editing.value,
            applies_to: editing.applies_to,
            min_subtotal: editing.min_subtotal ?? null,
            max_redemptions: editing.max_redemptions ?? null,
            per_household_limit: editing.per_household_limit ?? null,
            starts_at: editing.starts_at?.slice(0, 16) ?? '',
            ends_at: editing.ends_at?.slice(0, 16) ?? '',
            active: editing.active,
          }
        : DEFAULTS,
    );
  }, [drawerOpen, editing, reset]);

  const onSubmit = handleSubmit(async (values) => {
    const payload: DiscountRequest = {
      code: values.code || null,
      kind: values.kind,
      value: values.value,
      applies_to: values.applies_to,
      min_subtotal: values.min_subtotal,
      max_redemptions: values.max_redemptions,
      per_household_limit: values.per_household_limit,
      starts_at: values.starts_at ? new Date(values.starts_at).toISOString() : null,
      ends_at: values.ends_at ? new Date(values.ends_at).toISOString() : null,
      active: values.active,
    };
    try {
      if (editing) {
        await update.mutateAsync({ id: editing.id, data: payload });
        toast({ title: 'Discount updated', variant: 'success' });
      } else {
        await create.mutateAsync({ data: payload });
        toast({ title: 'Discount created', variant: 'success' });
      }
      setDrawerOpen(false);
    } catch (error) {
      const applied = applyApiFieldErrors(error, { setError, fallbackField: 'code' });
      if (!applied.handled) toast({ title: errorMessage(error), variant: 'danger' });
    }
  });

  const confirmArchive = async () => {
    if (!pendingArchive) return;
    try {
      await archive.mutateAsync({ id: pendingArchive.id });
      toast({ title: 'Discount archived', variant: 'success' });
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    } finally {
      setPendingArchive(null);
    }
  };

  const displayValue = (discount: DiscountResponse) =>
    discount.kind === 'percent'
      ? `${discount.value}%`
      : `Fixed (${(discount.value / 100).toFixed(2)})`;

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title="Discounts"
        description="Codes customers enter, or automatic discounts applied at checkout."
        actions={
          <Button
            onClick={() => {
              setEditing(null);
              setDrawerOpen(true);
            }}
          >
            <Plus className="h-4 w-4" aria-hidden="true" />
            Add discount
          </Button>
        }
      />

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {discounts.length === 0 ? (
          <EmptyState
            title="No discounts yet"
            description="Create a promo code or automatic discount."
          />
        ) : (
          <Table
            caption="Discounts"
            rowKey={(row) => row.id}
            columns={[
              {
                key: 'code',
                header: 'Code',
                cell: (row) => row.code ?? <Badge variant="secondary">Automatic</Badge>,
              },
              { key: 'kind', header: 'Kind', cell: (row) => row.kind },
              { key: 'value', header: 'Value', cell: displayValue },
              {
                key: 'applies',
                header: 'Applies to',
                cell: (row) => row.applies_to.replace('_', ' '),
              },
              {
                key: 'usage',
                header: 'Max uses',
                cell: (row) => row.max_redemptions ?? 'Unlimited',
              },
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
            data={discounts}
          />
        )}
      </QueryState>

      <Drawer
        open={drawerOpen}
        onOpenChange={setDrawerOpen}
        title={editing ? 'Edit discount' : 'Add discount'}
        footer={
          <>
            <Button variant="outline" onClick={() => setDrawerOpen(false)}>
              Cancel
            </Button>
            <Button onClick={() => void onSubmit()} disabled={create.isPending || update.isPending}>
              Save discount
            </Button>
          </>
        }
      >
        <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
          <FormField label="Code" help="Leave blank to apply automatically.">
            <Input {...register('code')} placeholder="SUMMER10" />
          </FormField>
          <div className="grid gap-4 sm:grid-cols-2">
            <FormField label="Kind">
              <Controller
                control={control}
                name="kind"
                render={({ field }) => (
                  <Select
                    aria-label="Kind"
                    value={field.value}
                    onValueChange={field.onChange}
                    options={[
                      { value: 'percent', label: 'Percentage' },
                      { value: 'fixed', label: 'Fixed amount' },
                    ]}
                  />
                )}
              />
            </FormField>
            <FormField label={kind === 'percent' ? 'Percent off' : 'Amount off'}>
              <Controller
                control={control}
                name="value"
                render={({ field }) =>
                  kind === 'percent' ? (
                    <Input
                      type="number"
                      aria-label="Percent off"
                      value={field.value}
                      onChange={(event) => field.onChange(Number(event.target.value))}
                    />
                  ) : (
                    <MoneyInput
                      aria-label="Amount off"
                      currency={currency}
                      value={field.value}
                      onChange={(value) => field.onChange(value ?? 0)}
                    />
                  )
                }
              />
            </FormField>
            <FormField label="Applies to">
              <Controller
                control={control}
                name="applies_to"
                render={({ field }) => (
                  <Select
                    aria-label="Applies to"
                    value={field.value}
                    onValueChange={field.onChange}
                    options={APPLIES_TO.map((option) => ({ ...option }))}
                  />
                )}
              />
            </FormField>
            <FormField label="Minimum subtotal">
              <Controller
                control={control}
                name="min_subtotal"
                render={({ field }) => (
                  <MoneyInput currency={currency} value={field.value} onChange={field.onChange} />
                )}
              />
            </FormField>
            <FormField label="Max redemptions">
              <Input type="number" {...register('max_redemptions')} />
            </FormField>
            <FormField label="Per-household limit">
              <Input type="number" {...register('per_household_limit')} />
            </FormField>
            <FormField label="Starts at">
              <Input type="datetime-local" {...register('starts_at')} />
            </FormField>
            <FormField label="Ends at">
              <Input type="datetime-local" {...register('ends_at')} />
            </FormField>
          </div>
          <Switch
            label="Active"
            checked={watch('active')}
            onCheckedChange={(checked) => setValue('active', checked)}
          />
          {editing ? (
            <p className="text-xs text-muted-foreground">
              Currently {displayValue(editing)} · {editing.applies_to.replace('_', ' ')}
            </p>
          ) : null}
        </form>
      </Drawer>

      <ConfirmDialog
        open={pendingArchive !== null}
        onOpenChange={(open) => !open && setPendingArchive(null)}
        title="Archive discount?"
        description="Archived discounts no longer apply at checkout. Orders that used them are unchanged."
        confirmLabel="Archive"
        destructive
        loading={archive.isPending}
        onConfirm={() => void confirmArchive()}
      />
    </div>
  );
}
