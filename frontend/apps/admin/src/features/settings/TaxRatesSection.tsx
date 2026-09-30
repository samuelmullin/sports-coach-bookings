import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { useState } from 'react';
import { applyApiFieldErrors } from '@scb/api-client';
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  ConfirmDialog,
  EmptyState,
  FormField,
  Input,
  Table,
  useToast,
} from '@scb/ui';
import {
  useArchiveTaxRate,
  useCreateTaxRate,
  useTaxRates,
  type TaxRateResponse,
} from '../../api/endpoints';
import { errorMessage, listItems, nextCursor } from '../shared/api-utils';
import { QueryState } from '../shared/QueryState';

const schema = z.object({
  name: z.string().min(1, 'Name is required'),
  rate_percent: z.coerce.number().min(0, 'Must be 0 or more').max(100, 'Must be 100 or less'),
});

type FormValues = z.infer<typeof schema>;

export function TaxRatesSection() {
  const query = useTaxRates();
  const create = useCreateTaxRate();
  const archive = useArchiveTaxRate();
  const { toast } = useToast();
  const [pendingArchiveId, setPendingArchiveId] = useState<string | null>(null);
  const rates = listItems<TaxRateResponse>(query);

  const {
    register,
    handleSubmit,
    reset,
    setError,
    formState: { errors },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { name: '', rate_percent: 0 },
  });

  const onSubmit = handleSubmit(async (values) => {
    try {
      await create.mutateAsync({
        data: { name: values.name, rate_bps: Math.round(values.rate_percent * 100) },
      });
      toast({ title: 'Tax rate added', variant: 'success' });
      reset({ name: '', rate_percent: 0 });
    } catch (error) {
      const applied = applyApiFieldErrors(error, {
        setError,
        mappedFields: { rate_bps: 'rate_percent' },
        fallbackField: 'name',
      });
      if (!applied.handled) toast({ title: errorMessage(error), variant: 'danger' });
    }
  });

  const confirmArchive = async () => {
    if (!pendingArchiveId) return;
    try {
      await archive.mutateAsync({ id: pendingArchiveId });
      toast({ title: 'Tax rate archived', variant: 'success' });
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    } finally {
      setPendingArchiveId(null);
    }
  };

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader>
          <CardTitle>Add a tax rate</CardTitle>
        </CardHeader>
        <CardContent>
          <form
            className="flex flex-col gap-4 sm:flex-row sm:items-end"
            onSubmit={onSubmit}
            noValidate
          >
            <FormField label="Name" required error={errors.name?.message} className="flex-1">
              <Input {...register('name')} placeholder="HST" />
            </FormField>
            <FormField
              label="Rate (%)"
              required
              error={errors.rate_percent?.message}
              className="w-40"
            >
              <Input type="number" step="0.001" {...register('rate_percent')} />
            </FormField>
            <Button type="submit" disabled={create.isPending}>
              Add rate
            </Button>
          </form>
        </CardContent>
      </Card>

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {rates.length === 0 ? (
          <EmptyState
            title="No tax rates yet"
            description="Add the sales tax rates that apply to your taxable items."
          />
        ) : (
          <Table
            caption="Tax rates"
            rowKey={(row) => row.id}
            columns={[
              { key: 'name', header: 'Name', cell: (row) => row.name },
              {
                key: 'rate',
                header: 'Rate',
                cell: (row) => `${(row.rate_bps / 100).toFixed(3)}%`,
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
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={() => setPendingArchiveId(row.id)}
                    disabled={!row.active}
                  >
                    Archive
                  </Button>
                ),
              },
            ]}
            data={rates}
          />
        )}
        {nextCursor(query) ? (
          <p className="text-xs text-muted-foreground">More tax rates available.</p>
        ) : null}
      </QueryState>

      <ConfirmDialog
        open={pendingArchiveId !== null}
        onOpenChange={(open) => !open && setPendingArchiveId(null)}
        title="Archive tax rate?"
        description="Archived rates are removed from new checkouts but remain on existing orders."
        confirmLabel="Archive"
        destructive
        loading={archive.isPending}
        onConfirm={() => void confirmArchive()}
      />
    </div>
  );
}
