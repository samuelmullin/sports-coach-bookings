import { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { Controller, useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { Plus } from 'lucide-react';
import { applyApiFieldErrors } from '@scb/api-client';
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
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
  useArchiveVariant,
  useCreateVariant,
  useProduct,
  useUpdateVariant,
  useVariants,
  type VariantSummary,
} from '../../api/endpoints';
import { body, errorMessage, listItems } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { useTenantSettings } from '../shared/useTenantSettings';

const schema = z.object({
  sku: z.string().min(1, 'SKU is required'),
  price: z.number().min(0),
  low_stock_threshold: z.coerce.number().min(0).nullable(),
  option_name: z.string(),
  option_value: z.string(),
  active: z.boolean(),
});

type FormValues = z.infer<typeof schema>;

const DEFAULTS: FormValues = {
  sku: '',
  price: 0,
  low_stock_threshold: null,
  option_name: '',
  option_value: '',
  active: true,
};

export function ProductEditorPage() {
  const { productId = '' } = useParams();
  const navigate = useNavigate();
  const { currency } = useTenantSettings();
  const { toast } = useToast();

  const productQuery = useProduct(productId);
  const variantsQuery = useVariants(productId);
  const create = useCreateVariant();
  const update = useUpdateVariant();
  const archive = useArchiveVariant();

  const product = body<{ id: string; name: string }>(productQuery);
  const variants = listItems<VariantSummary>(variantsQuery);

  const [drawerOpen, setDrawerOpen] = useState(false);
  const [editing, setEditing] = useState<VariantSummary | null>(null);

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
    if (editing) {
      const optionEntries = Object.entries(editing.option_values ?? {});
      reset({
        sku: editing.sku,
        price: editing.price,
        low_stock_threshold: editing.low_stock_threshold ?? null,
        option_name: optionEntries[0]?.[0] ?? '',
        option_value: optionEntries[0]?.[1] ?? '',
        active: editing.active,
      });
    } else {
      reset(DEFAULTS);
    }
  }, [drawerOpen, editing, reset]);

  const onSubmit = handleSubmit(async (values) => {
    const option_values = values.option_name
      ? { [values.option_name]: values.option_value }
      : undefined;
    try {
      if (editing) {
        await update.mutateAsync({
          id: editing.id,
          data: {
            sku: values.sku,
            price: values.price,
            low_stock_threshold: values.low_stock_threshold,
            option_values,
            active: values.active,
          },
        });
        toast({ title: 'Variant updated', variant: 'success' });
      } else {
        await create.mutateAsync({
          productId,
          data: {
            sku: values.sku,
            price: values.price,
            low_stock_threshold: values.low_stock_threshold,
            option_values,
            active: values.active,
          },
        });
        toast({ title: 'Variant created', variant: 'success' });
      }
      setDrawerOpen(false);
    } catch (error) {
      const applied = applyApiFieldErrors(error, { setError, fallbackField: 'sku' });
      if (!applied.handled) toast({ title: errorMessage(error), variant: 'danger' });
    }
  });

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title={product?.name ?? 'Product'}
        description="Variants, SKUs and prices."
        actions={
          <div className="flex gap-2">
            <Button variant="outline" size="sm" onClick={() => navigate('/inventory/products')}>
              Back
            </Button>
            <Button
              size="sm"
              onClick={() => {
                setEditing(null);
                setDrawerOpen(true);
              }}
            >
              <Plus className="h-4 w-4" aria-hidden="true" />
              Add variant
            </Button>
          </div>
        }
      />

      <Card>
        <CardHeader>
          <CardTitle>Variants</CardTitle>
        </CardHeader>
        <CardContent>
          {variants.length === 0 ? (
            <EmptyState
              title="No variants"
              description="Add at least one variant to sell this product."
            />
          ) : (
            <Table
              caption="Product variants"
              rowKey={(row) => row.id}
              columns={[
                { key: 'sku', header: 'SKU', cell: (row) => row.sku },
                {
                  key: 'options',
                  header: 'Options',
                  cell: (row) =>
                    Object.entries(row.option_values ?? {})
                      .map(([key, value]) => `${key}: ${value}`)
                      .join(', ') || '—',
                },
                {
                  key: 'price',
                  header: 'Price',
                  align: 'right',
                  cell: (row) => <MoneyDisplay amountMinor={row.price} currency={currency} />,
                },
                {
                  key: 'threshold',
                  header: 'Low stock at',
                  cell: (row) => row.low_stock_threshold ?? '—',
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
                        onClick={() =>
                          void archive
                            .mutateAsync({ id: row.id })
                            .then(() => toast({ title: 'Variant archived', variant: 'success' }))
                            .catch((error) =>
                              toast({ title: errorMessage(error), variant: 'danger' }),
                            )
                        }
                      >
                        Archive
                      </Button>
                    </div>
                  ),
                },
              ]}
              data={variants}
            />
          )}
        </CardContent>
      </Card>

      <Drawer
        open={drawerOpen}
        onOpenChange={setDrawerOpen}
        title={editing ? 'Edit variant' : 'Add variant'}
        footer={
          <>
            <Button variant="outline" onClick={() => setDrawerOpen(false)}>
              Cancel
            </Button>
            <Button onClick={() => void onSubmit()} disabled={create.isPending || update.isPending}>
              Save variant
            </Button>
          </>
        }
      >
        <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
          <FormField label="SKU" required error={errors.sku?.message}>
            <Input {...register('sku')} />
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
          <FormField label="Low stock threshold">
            <Input
              type="number"
              {...register('low_stock_threshold', {
                setValueAs: (value) => (value === '' ? null : Number(value)),
              })}
            />
          </FormField>
          <div className="grid gap-4 sm:grid-cols-2">
            <FormField label="Option name">
              <Input {...register('option_name')} placeholder="size" />
            </FormField>
            <FormField label="Option value">
              <Input {...register('option_value')} placeholder="YM" />
            </FormField>
          </div>
          <Switch
            label="Active"
            checked={watch('active')}
            onCheckedChange={(v) => setValue('active', v)}
          />
        </form>
      </Drawer>
    </div>
  );
}
