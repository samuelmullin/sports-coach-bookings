import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { applyApiFieldErrors } from '@scb/api-client';
import { Button, FormField, Input, Modal, Select, useToast } from '@scb/ui';
import { useInviteTeamMember } from '../../api/endpoints';
import { errorMessage } from '../shared/api-utils';

const schema = z.object({
  email: z.string().email('Enter a valid email'),
  role: z.enum(['admin', 'coach', 'owner']),
});

type FormValues = z.infer<typeof schema>;

export function InviteMemberDialog({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const invite = useInviteTeamMember();
  const { toast } = useToast();
  const {
    register,
    handleSubmit,
    reset,
    setError,
    watch,
    setValue,
    formState: { errors },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { email: '', role: 'coach' },
  });

  const onSubmit = handleSubmit(async (values) => {
    try {
      await invite.mutateAsync({ data: values });
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
      title="Invite a team member"
      description="They will receive an email invitation to join this business."
      footer={
        <>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button onClick={() => void onSubmit()} disabled={invite.isPending}>
            {invite.isPending ? 'Sending…' : 'Send invitation'}
          </Button>
        </>
      }
    >
      <form id="invite-member-form" className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
        <FormField label="Email" required error={errors.email?.message}>
          <Input type="email" {...register('email')} />
        </FormField>
        <FormField label="Role" required error={errors.role?.message}>
          <Select
            aria-label="Role"
            value={watch('role')}
            onValueChange={(value) => setValue('role', value as FormValues['role'])}
            options={[
              { value: 'coach', label: 'Coach' },
              { value: 'admin', label: 'Admin' },
              { value: 'owner', label: 'Owner' },
            ]}
          />
        </FormField>
      </form>
    </Modal>
  );
}
