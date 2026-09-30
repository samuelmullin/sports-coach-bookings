import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { applyApiFieldErrors } from '@scb/api-client';
import { Button, FormField, Input, useToast } from '@scb/ui';
import { useUpdatePassword } from '../../api/endpoints';
import { errorMessage } from '../shared/api-utils';

const schema = z
  .object({
    password: z.string().min(12, 'Password must be at least 12 characters'),
    confirm: z.string(),
  })
  .refine((values) => values.password === values.confirm, {
    message: 'Passwords do not match',
    path: ['confirm'],
  });

type FormValues = z.infer<typeof schema>;

export function PasswordForm() {
  const mutation = useUpdatePassword();
  const { toast } = useToast();

  const {
    register,
    handleSubmit,
    reset,
    setError,
    formState: { errors },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { password: '', confirm: '' },
  });

  const onSubmit = handleSubmit(async (values) => {
    try {
      await mutation.mutateAsync({ data: { password: values.password } });
      reset();
      toast({ title: 'Password updated', variant: 'success' });
    } catch (error) {
      const applied = applyApiFieldErrors(error, { setError, fallbackField: 'password' });
      if (!applied.handled) toast({ title: errorMessage(error), variant: 'danger' });
    }
  });

  return (
    <form className="flex max-w-md flex-col gap-4" onSubmit={onSubmit} noValidate>
      <FormField
        label="New password"
        required
        error={errors.password?.message}
        help="At least 12 characters."
      >
        <Input type="password" autoComplete="new-password" {...register('password')} />
      </FormField>
      <FormField label="Confirm new password" required error={errors.confirm?.message}>
        <Input type="password" autoComplete="new-password" {...register('confirm')} />
      </FormField>
      <div>
        <Button type="submit" disabled={mutation.isPending}>
          {mutation.isPending ? 'Saving…' : 'Change password'}
        </Button>
      </div>
    </form>
  );
}
