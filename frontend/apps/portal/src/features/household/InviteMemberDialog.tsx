import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { applyApiFieldErrors } from '@scb/api-client';
import { Button, FormField, Input, Modal, useToast } from '@scb/ui';
import { householdInvitesQueryKey, useInviteHouseholdMember } from '../../api/endpoints';
import { errorMessage } from '../shared/api-utils';

const schema = z.object({
  email: z.string().email('Enter a valid email address'),
  relationship: z.string().optional(),
});

type FormValues = z.infer<typeof schema>;

export function InviteMemberDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const mutation = useInviteHouseholdMember();
  const queryClient = useQueryClient();
  const { toast } = useToast();

  const {
    register,
    handleSubmit,
    reset,
    setError,
    formState: { errors },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { email: '', relationship: '' },
  });

  const onSubmit = handleSubmit(async (values) => {
    try {
      await mutation.mutateAsync({
        data: { email: values.email, relationship: values.relationship || null },
      });
      await queryClient.invalidateQueries({ queryKey: householdInvitesQueryKey() });
      toast({ title: `Invitation sent to ${values.email}`, variant: 'success' });
      reset();
      onOpenChange(false);
    } catch (error) {
      const applied = applyApiFieldErrors(error, { setError, fallbackField: 'email' });
      if (!applied.handled) toast({ title: errorMessage(error), variant: 'danger' });
    }
  });

  return (
    <Modal
      open={open}
      onOpenChange={onOpenChange}
      title="Invite an adult"
      description="They will receive an email invitation to join your household."
      footer={
        <>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button onClick={() => void onSubmit()} disabled={mutation.isPending}>
            {mutation.isPending ? 'Sending…' : 'Send invitation'}
          </Button>
        </>
      }
    >
      <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
        <FormField label="Email" required error={errors.email?.message}>
          <Input type="email" autoComplete="email" {...register('email')} />
        </FormField>
        <FormField
          label="Relationship"
          error={errors.relationship?.message}
          help="For example: Parent, Guardian, Grandparent."
        >
          <Input {...register('relationship')} />
        </FormField>
      </form>
    </Modal>
  );
}
