import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useForm } from 'react-hook-form';
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
  FileUpload,
  FormField,
  Input,
  Switch,
  Table,
  useToast,
} from '@scb/ui';
import {
  useArchiveProduct,
  useCreateInventoryUpload,
  useCreateProduct,
  useProducts,
  useUpdateProduct,
  type InventoryUpload,
  type ProductSummary,
} from '../../api/endpoints';
import { errorMessage, listItems, responseData } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';

const schema = z.object({
  name: z.string().min(1, 'Name is required'),
  description: z.string(),
  image_keys: z.array(z.string()),
  taxable: z.boolean(),
  visible_in_portal: z.boolean(),
  active: z.boolean(),
});

type FormValues = z.infer<typeof schema>;

const DEFAULTS: FormValues = {
  name: '',
  description: '',
  image_keys: [],
  taxable: true,
  visible_in_portal: true,
  active: true,
};

export function ProductsPage() {
  const query = useProducts();
  const create = useCreateProduct();
  const update = useUpdateProduct();
  const archive = useArchiveProduct();
  const upload = useCreateInventoryUpload();
  const { toast } = useToast();
  const navigate = useNavigate();

  const [editing, setEditing] = useState<ProductSummary | null>(null);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [pendingArchive, setPendingArchive] = useState<ProductSummary | null>(null);

  const products = listItems<ProductSummary>(query);
  const { register, handleSubmit, reset, setError, watch, setValue } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: DEFAULTS,
  });

  useEffect(() => {
    if (!drawerOpen) return;
    reset(
      editing
        ? {
            name: editing.name,
            description: editing.description ?? '',
            image_keys: editing.image_keys ?? [],
            taxable: editing.taxable ?? true,
            visible_in_portal: editing.visible_in_portal,
            active: editing.active,
          }
        : DEFAULTS,
    );
  }, [drawerOpen, editing, reset]);

  const onSubmit = handleSubmit(async (values) => {
    try {
      if (editing) {
        await update.mutateAsync({
          id: editing.id,
          data: { ...values, description: values.description || null },
        });
        toast({ title: 'Product updated', variant: 'success' });
      } else {
        await create.mutateAsync({ data: { ...values, description: values.description || null } });
        toast({ title: 'Product created', variant: 'success' });
      }
      setDrawerOpen(false);
    } catch (error) {
      const applied = applyApiFieldErrors(error, { setError, fallbackField: 'name' });
      if (!applied.handled) toast({ title: errorMessage(error), variant: 'danger' });
    }
  });

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title="Products"
        description="Merchandise and other physical goods."
        actions={
          <Button
            onClick={() => {
              setEditing(null);
              setDrawerOpen(true);
            }}
          >
            <Plus className="h-4 w-4" aria-hidden="true" />
            Add product
          </Button>
        }
      />

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {products.length === 0 ? (
          <EmptyState title="No products yet" description="Add a product and its variants." />
        ) : (
          <Table
            caption="Products"
            rowKey={(row) => row.id}
            columns={[
              {
                key: 'name',
                header: 'Name',
                cell: (row) => (
                  <Link
                    className="font-medium text-primary hover:underline"
                    to={`/inventory/products/${row.id}`}
                  >
                    {row.name}
                  </Link>
                ),
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
                      onClick={() => navigate(`/inventory/products/${row.id}`)}
                    >
                      Variants
                    </Button>
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
            data={products}
          />
        )}
      </QueryState>

      <Drawer
        open={drawerOpen}
        onOpenChange={setDrawerOpen}
        title={editing ? 'Edit product' : 'Add product'}
        footer={
          <>
            <Button variant="outline" onClick={() => setDrawerOpen(false)}>
              Cancel
            </Button>
            <Button onClick={() => void onSubmit()} disabled={create.isPending || update.isPending}>
              Save product
            </Button>
          </>
        }
      >
        <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
          <FormField label="Name" required error={undefined}>
            <Input {...register('name')} />
          </FormField>
          <FormField label="Description">
            <Input {...register('description')} />
          </FormField>
          <FormField label="Images">
            <FileUpload
              label="Upload product image"
              accept="image/*"
              getPresignedUrl={async (file) => {
                const result = await upload.mutateAsync({
                  data: {
                    filename: file.name,
                    content_type: (file.type || 'image/png') as never,
                    byte_size: file.size,
                  },
                });
                const payload = responseData<InventoryUpload>(result);
                if (!payload) throw new Error('Upload could not be prepared');
                setValue('image_keys', [...watch('image_keys'), payload.key]);
                return {
                  uploadUrl: payload.upload_url,
                  fileUrl: payload.key,
                  key: payload.key,
                  headers: (payload.headers as Record<string, string>) ?? {},
                };
              }}
            />
          </FormField>
          <div className="flex gap-6">
            <Switch
              label="Taxable"
              checked={watch('taxable')}
              onCheckedChange={(v) => setValue('taxable', v)}
            />
            <Switch
              label="Visible in portal"
              checked={watch('visible_in_portal')}
              onCheckedChange={(v) => setValue('visible_in_portal', v)}
            />
            <Switch
              label="Active"
              checked={watch('active')}
              onCheckedChange={(v) => setValue('active', v)}
            />
          </div>
        </form>
      </Drawer>

      <ConfirmDialog
        open={pendingArchive !== null}
        onOpenChange={(open) => !open && setPendingArchive(null)}
        title="Archive product?"
        description="Archived products can no longer be purchased. Existing orders are unaffected."
        confirmLabel="Archive"
        destructive
        loading={archive.isPending}
        onConfirm={() => {
          if (!pendingArchive) return;
          void archive
            .mutateAsync({ id: pendingArchive.id })
            .then(() => toast({ title: 'Product archived', variant: 'success' }))
            .catch((error) => toast({ title: errorMessage(error), variant: 'danger' }))
            .finally(() => setPendingArchive(null));
        }}
      />
    </div>
  );
}
