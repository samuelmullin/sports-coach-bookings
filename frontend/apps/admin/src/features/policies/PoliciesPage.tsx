import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
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
  FormField,
  Input,
  Table,
  Textarea,
  useToast,
} from '@scb/ui';
import {
  useArchivePolicy,
  useCreatePolicy,
  usePolicies,
  useSetDefaultPolicy,
  type PolicyResponse,
} from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';
import { defaultPolicyRules } from './defaults';

const schema = z.object({
  name: z.string().min(1, 'Name is required'),
  customer_facing_summary: z.string(),
});

type FormValues = z.infer<typeof schema>;

export function PoliciesPage() {
  const query = usePolicies();
  const create = useCreatePolicy();
  const archive = useArchivePolicy();
  const setDefault = useSetDefaultPolicy();
  const { toast } = useToast();
  const navigate = useNavigate();

  const [drawerOpen, setDrawerOpen] = useState(false);
  const [pendingArchive, setPendingArchive] = useState<PolicyResponse | null>(null);

  const policies = listItems<PolicyResponse>(query);
  const {
    register,
    handleSubmit,
    reset,
    setError,
    formState: { errors },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { name: '', customer_facing_summary: '' },
  });

  const onSubmit = handleSubmit(async (values) => {
    try {
      const result = await create.mutateAsync({
        data: {
          name: values.name,
          customer_facing_summary: values.customer_facing_summary || null,
          rules: defaultPolicyRules,
        },
      });
      toast({ title: 'Policy created', variant: 'success' });
      reset();
      setDrawerOpen(false);
      const created = result as { data?: { id?: string } };
      const id = created.data?.id;
      if (id) navigate(`/policies/${id}`);
    } catch (error) {
      const applied = applyApiFieldErrors(error, { setError, fallbackField: 'name' });
      if (!applied.handled) toast({ title: errorMessage(error), variant: 'danger' });
    }
  });

  const confirmArchive = async () => {
    if (!pendingArchive) return;
    try {
      await archive.mutateAsync({ id: pendingArchive.id });
      toast({ title: 'Policy archived', variant: 'success' });
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    } finally {
      setPendingArchive(null);
    }
  };

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title="Cancellation policies"
        description="Define what happens when customers cancel, rebook or don't show."
        actions={
          <Button onClick={() => setDrawerOpen(true)}>
            <Plus className="h-4 w-4" aria-hidden="true" />
            New policy
          </Button>
        }
      />

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {policies.length === 0 ? (
          <EmptyState
            title="No policies yet"
            description="Every business gets a default policy. Create one to customise it."
          />
        ) : (
          <Table
            caption="Cancellation policies"
            rowKey={(row) => row.id}
            columns={[
              {
                key: 'name',
                header: 'Name',
                cell: (row) => (
                  <div className="flex items-center gap-2">
                    <span className="font-medium">{row.name}</span>
                    {row.is_default ? <Badge variant="accent">Default</Badge> : null}
                  </div>
                ),
              },
              { key: 'version', header: 'Version', cell: (row) => `v${row.version}` },
              {
                key: 'assigned',
                header: 'Offerings',
                cell: (row) => row.assigned_offering_ids?.length ?? 0,
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
                      onClick={() => navigate(`/policies/${row.id}`)}
                    >
                      Edit
                    </Button>
                    {!row.is_default ? (
                      <Button
                        variant="ghost"
                        size="sm"
                        onClick={() =>
                          void setDefault
                            .mutateAsync({ id: row.id })
                            .then(() =>
                              toast({ title: 'Default policy updated', variant: 'success' }),
                            )
                            .catch((error) =>
                              toast({ title: errorMessage(error), variant: 'danger' }),
                            )
                        }
                      >
                        Set default
                      </Button>
                    ) : null}
                    <Button
                      variant="ghost"
                      size="sm"
                      disabled={!row.active || row.is_default}
                      onClick={() => setPendingArchive(row)}
                    >
                      Archive
                    </Button>
                  </div>
                ),
              },
            ]}
            data={policies}
          />
        )}
      </QueryState>

      <Drawer
        open={drawerOpen}
        onOpenChange={setDrawerOpen}
        title="New policy"
        footer={
          <>
            <Button variant="outline" onClick={() => setDrawerOpen(false)}>
              Cancel
            </Button>
            <Button onClick={() => void onSubmit()} disabled={create.isPending}>
              Create policy
            </Button>
          </>
        }
      >
        <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
          <FormField label="Name" required error={errors.name?.message}>
            <Input {...register('name')} placeholder="Standard policy" />
          </FormField>
          <FormField label="Customer-facing summary" help="Shown to customers at checkout.">
            <Textarea {...register('customer_facing_summary')} />
          </FormField>
        </form>
      </Drawer>

      <ConfirmDialog
        open={pendingArchive !== null}
        onOpenChange={(open) => !open && setPendingArchive(null)}
        title="Archive policy?"
        description="Archived policies can't be assigned to offerings. Existing bookings keep their snapshot."
        confirmLabel="Archive"
        destructive
        loading={archive.isPending}
        onConfirm={() => void confirmArchive()}
      />
    </div>
  );
}
