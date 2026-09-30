import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useFieldArray, useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { Plus, Trash2 } from 'lucide-react';
import {
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  EmptyState,
  FormField,
  Input,
  Select,
  useToast,
} from '@scb/ui';
import {
  useCreateOfflineOrder,
  useOfferings,
  usePackages,
  useProducts,
  useHouseholds,
} from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';

const schema = z.object({
  household_id: z.string().min(1, 'Choose a household'),
  discount_code: z.string(),
  note: z.string(),
  lines: z.array(
    z.object({
      type: z.enum(['package', 'product', 'drop_in']),
      ref_id: z.string().min(1, 'Choose an item'),
      quantity: z.coerce.number().min(1),
    }),
  ),
});

type FormValues = z.infer<typeof schema>;

export function OfflineOrderPage() {
  const navigate = useNavigate();
  const { toast } = useToast();
  const [q, setQ] = useState('');
  const households = listItems<{ id?: string; name?: string | null }>(
    useHouseholds({ q: q || undefined, limit: 10 }),
  );
  const packages = listItems<{ id: string; name: string }>(usePackages());
  const offerings = listItems<{ id: string; name: string }>(useOfferings());
  const products = listItems<{ id: string; name: string }>(useProducts());
  const create = useCreateOfflineOrder();

  const { register, control, handleSubmit, watch, setValue } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      household_id: '',
      discount_code: '',
      note: '',
      lines: [{ type: 'package', ref_id: '', quantity: 1 }],
    },
  });
  const { fields, append, remove } = useFieldArray({ control, name: 'lines' });

  const onSubmit = handleSubmit(async (values) => {
    try {
      const result = await create.mutateAsync({
        data: {
          household_id: values.household_id,
          discount_code: values.discount_code || null,
          note: values.note || null,
          lines: values.lines.map((line) => ({
            type: line.type,
            ref_id: line.ref_id,
            quantity: line.quantity,
          })),
        },
      });
      const created = (result as { data?: { id?: string } }).data;
      toast({ title: 'Offline order created', variant: 'success' });
      if (created?.id) navigate(`/orders/${created.id}`);
      else navigate('/orders');
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    }
  });

  const optionsFor = (type: string) => {
    if (type === 'package') return packages.map((p) => ({ value: p.id, label: p.name }));
    if (type === 'product') return products.map((p) => ({ value: p.id, label: p.name }));
    return offerings.map((o) => ({ value: o.id, label: o.name }));
  };

  return (
    <div className="flex flex-col gap-4">
      <PageHeader title="New offline order" description="Record a sale taken outside the portal." />

      <Card>
        <CardHeader>
          <CardTitle>Household</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-3">
          <FormField label="Search">
            <Input
              aria-label="Search households"
              value={q}
              onChange={(event) => setQ(event.target.value)}
              placeholder="Search households"
            />
          </FormField>
          <Select
            aria-label="Household"
            placeholder="Choose a household"
            value={watch('household_id')}
            onValueChange={(value) => setValue('household_id', value)}
            options={households
              .filter((household) => household.id)
              .map((household) => ({
                value: household.id as string,
                label: household.name ?? 'Unnamed',
              }))}
          />
        </CardContent>
      </Card>

      <Card>
        <CardHeader className="flex-row items-center justify-between">
          <CardTitle>Lines</CardTitle>
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={() => append({ type: 'package', ref_id: '', quantity: 1 })}
          >
            <Plus className="h-3.5 w-3.5" aria-hidden="true" />
            Add line
          </Button>
        </CardHeader>
        <CardContent className="flex flex-col gap-3">
          {fields.length === 0 ? (
            <EmptyState title="No lines" description="Add at least one line." />
          ) : (
            fields.map((field, index) => {
              const type = watch(`lines.${index}.type`);
              return (
                <div key={field.id} className="grid grid-cols-[1fr_2fr_auto_auto] items-end gap-2">
                  <FormField label="Type">
                    <Select
                      aria-label={`Line ${index + 1} type`}
                      value={type}
                      onValueChange={(value) => {
                        setValue(
                          `lines.${index}.type`,
                          value as FormValues['lines'][number]['type'],
                        );
                        setValue(`lines.${index}.ref_id`, '');
                      }}
                      options={[
                        { value: 'package', label: 'Package' },
                        { value: 'product', label: 'Product' },
                        { value: 'drop_in', label: 'Drop-in' },
                      ]}
                    />
                  </FormField>
                  <FormField label="Item">
                    <Select
                      aria-label={`Line ${index + 1} item`}
                      value={watch(`lines.${index}.ref_id`)}
                      onValueChange={(value) => setValue(`lines.${index}.ref_id`, value)}
                      options={optionsFor(type)}
                    />
                  </FormField>
                  <FormField label="Qty">
                    <Input
                      type="number"
                      aria-label={`Line ${index + 1} quantity`}
                      className="w-20"
                      {...register(`lines.${index}.quantity`)}
                    />
                  </FormField>
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    aria-label={`Remove line ${index + 1}`}
                    onClick={() => remove(index)}
                  >
                    <Trash2 className="h-4 w-4" />
                  </Button>
                </div>
              );
            })
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Details</CardTitle>
        </CardHeader>
        <CardContent className="grid gap-4 sm:grid-cols-2">
          <FormField label="Discount code">
            <Input {...register('discount_code')} />
          </FormField>
          <FormField label="Note">
            <Input {...register('note')} />
          </FormField>
        </CardContent>
      </Card>

      <div className="flex justify-end">
        <Button onClick={() => void onSubmit()} disabled={create.isPending}>
          Create order
        </Button>
      </div>
    </div>
  );
}
