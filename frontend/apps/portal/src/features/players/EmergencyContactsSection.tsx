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
  emergencyContactsQueryKey,
  useCreateEmergencyContact,
  useDeleteEmergencyContact,
  useEmergencyContacts,
  useUpdateEmergencyContact,
  type EmergencyContactResponse,
} from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { QueryState } from '../shared/QueryState';
import { useCustomerAuth } from '../../auth/customer-auth';

const schema = z.object({
  name: z.string().min(1, 'Name is required'),
  phone: z.string().min(1, 'Phone is required'),
  alt_phone: z.string().optional(),
  relationship: z.string().optional(),
});
type FormValues = z.infer<typeof schema>;

export function EmergencyContactsSection({ playerId }: { playerId: string }) {
  const query = useEmergencyContacts(playerId);
  const create = useCreateEmergencyContact();
  const update = useUpdateEmergencyContact();
  const remove = useDeleteEmergencyContact();
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const { customerUser } = useCustomerAuth();

  const [editing, setEditing] = useState<EmergencyContactResponse | null>(null);
  const [open, setOpen] = useState(false);
  const [pendingDelete, setPendingDelete] = useState<EmergencyContactResponse | null>(null);

  const contacts = listItems<EmergencyContactResponse>(query);

  const form = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { name: '', phone: '', alt_phone: '', relationship: '' },
  });

  const openCreate = () => {
    form.reset({ name: '', phone: '', alt_phone: '', relationship: '' });
    setEditing(null);
    setOpen(true);
  };

  const openEdit = (contact: EmergencyContactResponse) => {
    form.reset({
      name: contact.name,
      phone: contact.phone,
      alt_phone: contact.alt_phone ?? '',
      relationship: contact.relationship ?? '',
    });
    setEditing(contact);
    setOpen(true);
  };

  const onSubmit = form.handleSubmit(async (values) => {
    const data = {
      name: values.name,
      phone: values.phone,
      alt_phone: values.alt_phone || null,
      relationship: values.relationship || null,
      priority: editing?.priority ?? contacts.length + 1,
    };
    try {
      if (editing) {
        await update.mutateAsync({ playerId, id: editing.id, data });
      } else {
        await create.mutateAsync({ playerId, data });
      }
      await queryClient.invalidateQueries({ queryKey: emergencyContactsQueryKey() });
      toast({ title: editing ? 'Contact updated' : 'Contact added', variant: 'success' });
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
      await queryClient.invalidateQueries({ queryKey: emergencyContactsQueryKey() });
      toast({ title: 'Contact removed', variant: 'success' });
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
          At least one emergency contact is required before booking.
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
        {contacts.length === 0 ? (
          <EmptyState title="No emergency contacts" description="Add a contact for safety." />
        ) : (
          <ul className="flex flex-col gap-2">
            {contacts.map((contact) => (
              <li key={contact.id}>
                <Card>
                  <CardContent className="flex flex-wrap items-center justify-between gap-3 pt-4">
                    <div className="flex flex-col gap-0.5 text-sm">
                      <span className="font-medium">
                        {contact.name}
                        {contact.relationship ? ` · ${contact.relationship}` : ''}
                      </span>
                      <span className="text-muted-foreground">{contact.phone}</span>
                      {contact.alt_phone ? (
                        <span className="text-xs text-muted-foreground">
                          Alt: {contact.alt_phone}
                        </span>
                      ) : null}
                    </div>
                    {customerUser ? (
                      <div className="flex items-center gap-1">
                        <Button
                          variant="ghost"
                          size="sm"
                          aria-label={`Edit ${contact.name}`}
                          onClick={() => openEdit(contact)}
                        >
                          <Pencil className="h-4 w-4" aria-hidden="true" />
                        </Button>
                        <Button
                          variant="ghost"
                          size="sm"
                          aria-label={`Remove ${contact.name}`}
                          onClick={() => setPendingDelete(contact)}
                        >
                          <Trash2 className="h-4 w-4" aria-hidden="true" />
                        </Button>
                      </div>
                    ) : null}
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
        title={editing ? 'Edit contact' : 'Add emergency contact'}
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
          <FormField label="Phone" required error={form.formState.errors.phone?.message}>
            <Input type="tel" {...form.register('phone')} />
          </FormField>
          <FormField label="Alternate phone">
            <Input type="tel" {...form.register('alt_phone')} />
          </FormField>
          <FormField label="Relationship">
            <Input {...form.register('relationship')} />
          </FormField>
        </form>
      </Modal>

      <ConfirmDialog
        open={pendingDelete !== null}
        onOpenChange={(next) => !next && setPendingDelete(null)}
        title="Remove contact?"
        description={`${pendingDelete?.name ?? 'This contact'} will no longer be listed.`}
        confirmLabel="Remove"
        destructive
        loading={remove.isPending}
        onConfirm={() => void confirmDelete()}
      />
    </div>
  );
}
