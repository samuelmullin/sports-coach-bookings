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
  Checkbox,
  ConfirmDialog,
  Drawer,
  EmptyState,
  FormField,
  Input,
  Select,
  Switch,
  Table,
  TabsView,
  useToast,
} from '@scb/ui';
import {
  useArchiveWaiverTemplate,
  useCreateWaiverTemplate,
  useOfferings,
  useWaiverSignatures,
  useWaiverTemplates,
  type WaiverTemplateResponse,
  waiverSignaturePdfUrl,
} from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';

const schema = z.object({
  name: z.string().min(1, 'Name is required'),
  scope: z.enum(['all_bookings', 'offerings']),
  require_resign_on_new_version: z.boolean(),
  offering_ids: z.array(z.string()),
});

type FormValues = z.infer<typeof schema>;

const DEFAULTS: FormValues = {
  name: '',
  scope: 'all_bookings',
  require_resign_on_new_version: true,
  offering_ids: [],
};

function TemplatesTab() {
  const query = useWaiverTemplates();
  const create = useCreateWaiverTemplate();
  const archive = useArchiveWaiverTemplate();
  const offerings = listItems<{ id: string; name: string }>(useOfferings());
  const { toast } = useToast();
  const navigate = useNavigate();

  const [drawerOpen, setDrawerOpen] = useState(false);
  const [pendingArchive, setPendingArchive] = useState<WaiverTemplateResponse | null>(null);

  const templates = listItems<WaiverTemplateResponse>(query);
  const {
    register,
    handleSubmit,
    reset,
    setError,
    watch,
    setValue,
    formState: { errors },
  } = useForm<FormValues>({ resolver: zodResolver(schema), defaultValues: DEFAULTS });

  const scope = watch('scope');

  const onSubmit = handleSubmit(async (values) => {
    try {
      await create.mutateAsync({
        data: {
          name: values.name,
          scope: values.scope,
          require_resign_on_new_version: values.require_resign_on_new_version,
          offering_ids: values.scope === 'offerings' ? values.offering_ids : null,
        },
      });
      toast({ title: 'Waiver template created', variant: 'success' });
      reset();
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
      toast({ title: 'Waiver template archived', variant: 'success' });
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    } finally {
      setPendingArchive(null);
    }
  };

  return (
    <div className="flex flex-col gap-4">
      <div className="flex justify-end">
        <Button onClick={() => setDrawerOpen(true)}>
          <Plus className="h-4 w-4" aria-hidden="true" />
          New waiver
        </Button>
      </div>

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {templates.length === 0 ? (
          <EmptyState
            title="No waivers yet"
            description="Create a waiver template that customers must sign before booking."
          />
        ) : (
          <Table
            caption="Waiver templates"
            rowKey={(row) => row.id}
            columns={[
              { key: 'name', header: 'Name', cell: (row) => row.name },
              {
                key: 'scope',
                header: 'Scope',
                cell: (row) =>
                  row.scope === 'all_bookings' ? 'All bookings' : 'Specific offerings',
              },
              {
                key: 'resign',
                header: 'Re-sign on new version',
                cell: (row) => (row.require_resign_on_new_version ? 'Yes' : 'No'),
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
                      onClick={() => navigate(`/waivers/${row.id}`)}
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
            data={templates}
          />
        )}
      </QueryState>

      <Drawer
        open={drawerOpen}
        onOpenChange={setDrawerOpen}
        title="New waiver template"
        footer={
          <>
            <Button variant="outline" onClick={() => setDrawerOpen(false)}>
              Cancel
            </Button>
            <Button onClick={() => void onSubmit()} disabled={create.isPending}>
              Create template
            </Button>
          </>
        }
      >
        <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
          <FormField label="Name" required error={errors.name?.message}>
            <Input {...register('name')} placeholder="Participation waiver" />
          </FormField>
          <FormField label="Applies to">
            <Select
              aria-label="Scope"
              value={scope}
              onValueChange={(value) => setValue('scope', value as FormValues['scope'])}
              options={[
                { value: 'all_bookings', label: 'All bookings' },
                { value: 'offerings', label: 'Specific offerings' },
              ]}
            />
          </FormField>
          {scope === 'offerings' ? (
            <div className="flex flex-col gap-2">
              {offerings.map((offering) => (
                <Checkbox
                  key={offering.id}
                  label={offering.name}
                  checked={watch('offering_ids').includes(offering.id)}
                  onCheckedChange={(checked) =>
                    setValue(
                      'offering_ids',
                      checked
                        ? [...watch('offering_ids'), offering.id]
                        : watch('offering_ids').filter((id) => id !== offering.id),
                    )
                  }
                />
              ))}
            </div>
          ) : null}
          <Switch
            label="Require customers to re-sign when a new version is published"
            checked={watch('require_resign_on_new_version')}
            onCheckedChange={(checked) => setValue('require_resign_on_new_version', checked)}
          />
        </form>
      </Drawer>

      <ConfirmDialog
        open={pendingArchive !== null}
        onOpenChange={(open) => !open && setPendingArchive(null)}
        title="Archive waiver?"
        description="Archived waivers are no longer required for new bookings. Existing signatures are kept."
        confirmLabel="Archive"
        destructive
        loading={archive.isPending}
        onConfirm={() => void confirmArchive()}
      />
    </div>
  );
}

function SignaturesTab() {
  const query = useWaiverSignatures({ limit: 25 });
  const signatures = listItems<{
    id: string;
    player_id: string;
    signer_name_typed: string;
    signed_at?: string;
    waiver_version_id: string;
  }>(query);

  return (
    <QueryState
      loading={query.isLoading}
      error={query.isError ? errorMessage(query.error) : undefined}
      onRetry={() => void query.refetch()}
    >
      {signatures.length === 0 ? (
        <EmptyState title="No signatures yet" description="Signed waivers will appear here." />
      ) : (
        <Table
          caption="Waiver signatures"
          rowKey={(row) => row.id}
          columns={[
            { key: 'signer', header: 'Signed by', cell: (row) => row.signer_name_typed },
            { key: 'player', header: 'Player', cell: (row) => row.player_id },
            {
              key: 'signed',
              header: 'Signed',
              cell: (row) => (row.signed_at ? new Date(row.signed_at).toLocaleString() : '—'),
            },
            {
              key: 'pdf',
              header: 'PDF',
              align: 'right',
              cell: (row) => (
                <a
                  className="text-sm font-medium text-primary hover:underline"
                  href={waiverSignaturePdfUrl(row.id)}
                  target="_blank"
                  rel="noreferrer"
                >
                  Download
                </a>
              ),
            },
          ]}
          data={signatures}
        />
      )}
    </QueryState>
  );
}

export function WaiversPage() {
  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title="Waivers"
        description="Templates customers sign, and the signatures on file."
      />
      <TabsView
        aria-label="Waiver sections"
        items={[
          { value: 'templates', label: 'Templates', content: <TemplatesTab /> },
          { value: 'signatures', label: 'Signatures', content: <SignaturesTab /> },
        ]}
      />
    </div>
  );
}
