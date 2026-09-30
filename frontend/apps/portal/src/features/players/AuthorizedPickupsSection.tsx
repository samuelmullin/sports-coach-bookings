import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { Pencil, Plus, Trash2 } from 'lucide-react';
import { applyApiFieldErrors } from '@scb/api-client';
import {
  Button,
  Card,
  CardContent,
  ConfirmDialog,
  EmptyState,
  FormField,
  Input,
  Modal,
  useToast,
} from '@scb/ui';
import {
  authorizedPickupsQueryKey,
  useAuthorizedPickups,
  useCreateAuthorizedPickup,
  useDeleteAuthorizedPickup,
  useUpdateAuthorizedPickup,
  type AuthorizedPickupResponse,
} from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { QueryState } from '../shared/QueryState';

const schema = z.object({
  name: z.string().min(1, 'Name is required'),
  phone: z.string().optional(),
  relationship: z.string().optional(),
  notes: z.string().optional(),
});
type FormValues = z.infer<typeof schema>;

export function AuthorizedPickupsSection({ playerId }: { playerId: string }) {
  const query = useAuthorizedPickups(playerId);
  const create = useCreateAuthorizedPickup();
  const update = useUpdateAuthorizedPickup();
  const remove = useDeleteAuthorizedPickup();
  const queryClient = useQueryClient();
  const { toast } = useToast();

  const [editing, setEditing] = useState<AuthorizedPickupResponse | null>(null);
  const [open, setOpen] = useState(false);
  const [pendingDelete, setPendingDelete] = useState<AuthorizedPickupResponse | null>(null);

  const pickups = listItems<AuthorizedPickupResponse>(query);
  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { name: '', phone: '', relationship: '', notes: '' },
  });

  const openCreate = () => {
    form.reset({ name: '', phone: '', relationship: '', notes: '' });
    setEditing(null);
    setOpen(true);
  };

  const openEdit = (pickup: AuthorizedPickupResponse) => {
    form.reset({
      name: pickup.name,
      phone: pickup.phone ?? '',
      relationship: pickup.relationship ?? '',
      notes: pickup.notes ?? '',
    });
    setEditing(pickup);
    setOpen(true);
  };

  const onSubmit = form.handleSubmit(async (values) => {
    const data = {
      name: values.name,
      phone: values.phone || null,
      relationship: values.relationship || null,
      notes: values.notes || null,
    };
    try {
      if (editing) {
        await update.mutateAsync({ playerId, id: editing.id, data });
      } else {
        await create.mutateAsync({ playerId, data });
      }
      await queryClient.invalidateQueries({ queryKey: authorizedPickupsQueryKey() });
      toast({ title: editing ? 'Pickup updated' : 'Pickup added', variant: 'success' });
      setOpen(false);
    } catch (error) {
      const applied = applyApiFieldErrors(error, {
        setError: form.setError,
        fallbackField: 'name',
      });
      if (!applied.handled) toast({ title: errorMessage(error), variant: 'danger' });
    }
  });

  const confirmDelete = async () => {
    if (!pendingDelete) return;
    try {
      await remove.mutateAsync({ playerId, id: pendingDelete.id });
      await queryClient.invalidateQueries({ queryKey: authorizedPickupsQueryKey() });
      toast({ title: 'Pickup removed', variant: 'success' });
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    } finally {
      setPendingDelete(null);
    }
  };

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-between">
        <p className="text-sm text-muted-foreground">
          People allowed to collect the player from sessions.
        </p>
        <Button size="sm" onClick={openCreate}>
          <Plus className="h-4 w-4" aria-hidden="true" /> Add
        </Button>
      </div>

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {pickups.length === 0 ? (
          <EmptyState
            title="No authorized pickups"
            description="Add people who may collect this player."
          />
        ) : (
          <ul className="flex flex-col gap-2">
            {pickups.map((pickup) => (
              <li key={pickup.id}>
                <Card>
                  <CardContent className="flex flex-wrap items-center justify-between gap-3 pt-4">
                    <div className="flex flex-col gap-0.5 text-sm">
                      <span className="font-medium">
                        {pickup.name}
                        {pickup.relationship ? ` · ${pickup.relationship}` : ''}
                      </span>
                      {pickup.phone ? (
                        <span className="text-muted-foreground">{pickup.phone}</span>
                      ) : null}
                      {pickup.notes ? (
                        <span className="text-xs text-muted-foreground">{pickup.notes}</span>
                      ) : null}
                    </div>
                    <div className="flex items-center gap-1">
                      <Button
                        variant="ghost"
                        size="sm"
                        aria-label={`Edit ${pickup.name}`}
                        onClick={() => openEdit(pickup)}
                      >
                        <Pencil className="h-4 w-4" aria-hidden="true" />
                      </Button>
                      <Button
                        variant="ghost"
                        size="sm"
                        aria-label={`Remove ${pickup.name}`}
                        onClick={() => setPendingDelete(pickup)}
                      >
                        <Trash2 className="h-4 w-4" aria-hidden="true" />
                      </Button>
                    </div>
                  </CardContent>
                </Card>
              </li>
            ))}
          </ul>
        )}
      </QueryState>

      <Modal
        open={open}
        onOpenChange={setOpen}
        title={editing ? 'Edit authorized pickup' : 'Add authorized pickup'}
        footer={
          <>
            <Button variant="outline" onClick={() => setOpen(false)}>
              Cancel
            </Button>
            <Button onClick={() => void onSubmit()} disabled={create.isPending || update.isPending}>
              Save
            </Button>
          </>
        }
      >
        <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
          <FormField label="Name" required error={form.formState.errors.name?.message}>
            <Input {...form.register('name')} />
          </FormField>
          <FormField label="Phone">
            <Input type="tel" {...form.register('phone')} />
          </FormField>
          <FormField label="Relationship">
            <Input {...form.register('relationship')} />
          </FormField>
          <FormField label="Notes">
            <Input {...form.register('notes')} />
          </FormField>
        </form>
      </Modal>

      <ConfirmDialog
        open={pendingDelete !== null}
        onOpenChange={(next) => !next && setPendingDelete(null)}
        title="Remove authorized pickup?"
        description={`${pendingDelete?.name ?? 'This person'} will no longer be able to collect the player.`}
        confirmLabel="Remove"
        destructive
        loading={remove.isPending}
        onConfirm={() => void confirmDelete()}
      />
    </div>
  );
}
