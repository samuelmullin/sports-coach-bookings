import { useEffect } from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { applyApiFieldErrors } from '@scb/api-client';
import { Button, FormField, Input, useToast } from '@scb/ui';
import { accountQueryKey, useUpdateEmail, type CustomerUser } from '../../api/endpoints';
import { errorMessage } from '../shared/api-utils';

const schema = z.object({
  email: z.string().email('Enter a valid email address'),
});

type FormValues = z.infer<typeof schema>;

export function EmailForm({ customerUser }: { customerUser?: CustomerUser }) {
  const mutation = useUpdateEmail();
  const queryClient = useQueryClient();
  const { toast } = useToast();

  const {
    register,
    handleSubmit,
    reset,
    setError,
    formState: { errors },
  } = useForm<FormValues>({ resolver: zodResolver(schema), defaultValues: { email: '' } });

  useEffect(() => {
    if (customerUser) reset({ email: customerUser.email });
  }, [customerUser, reset]);

  const onSubmit = handleSubmit(async (values) => {
    try {
      await mutation.mutateAsync({ data: { email: values.email } });
      await queryClient.invalidateQueries({ queryKey: accountQueryKey() });
      toast({
        title: 'Check your inbox',
        description: 'We sent a confirmation link to your new email address.',
        variant: 'success',
      });
    } catch (error) {
      const applied = applyApiFieldErrors(error, { setError, fallbackField: 'email' });
      if (!applied.handled) toast({ title: errorMessage(error), variant: 'danger' });
    }
  });

  return (
    <form className="flex max-w-md flex-col gap-4" onSubmit={onSubmit} noValidate>
      <FormField
        label="Email address"
        required
        error={errors.email?.message}
        help="Changing your email requires you to confirm the new address."
      >
        <Input type="email" autoComplete="email" {...register('email')} />
      </FormField>
      <div>
        <Button type="submit" disabled={mutation.isPending}>
          {mutation.isPending ? 'Sending…' : 'Update email'}
        </Button>
      </div>
    </form>
  );
}
