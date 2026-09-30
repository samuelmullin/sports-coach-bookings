import { useEffect } from 'react';
import { Controller, useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { applyApiFieldErrors } from '@scb/api-client';
import {
  Button,
  FormField,
  Input,
  PhoneInput,
  defaultPhoneCountry,
  isValidPhoneValue,
  phoneDigits,
  phoneErrorMessage,
  splitE164,
  useToast,
} from '@scb/ui';
import { accountQueryKey, useUpdateAccount, type CustomerUser } from '../../api/endpoints';
import { errorMessage } from '../shared/api-utils';

const phoneSchema = z
  .object({ country: z.string(), national: z.string() })
  .refine(isValidPhoneValue, { message: phoneErrorMessage });

const schema = z.object({
  first_name: z.string().min(1, 'First name is required'),
  last_name: z.string().min(1, 'Last name is required'),
  phone: phoneSchema,
});

type FormValues = z.infer<typeof schema>;

export function ProfileForm({ customerUser }: { customerUser?: CustomerUser }) {
  const mutation = useUpdateAccount();
  const queryClient = useQueryClient();
  const { toast } = useToast();

  const {
    register,
    handleSubmit,
    reset,
    control,
    setError,
    formState: { errors },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      first_name: '',
      last_name: '',
      phone: { country: defaultPhoneCountry, national: '' },
    },
  });

  useEffect(() => {
    if (customerUser) {
      reset({
        first_name: customerUser.first_name,
        last_name: customerUser.last_name,
        phone: splitE164(customerUser.phone) ?? { country: defaultPhoneCountry, national: '' },
      });
    }
  }, [customerUser, reset]);

  const onSubmit = handleSubmit(async (values) => {
    try {
      await mutation.mutateAsync({
        data: {
          first_name: values.first_name,
          last_name: values.last_name,
          phone: values.phone.national ? phoneDigits(values.phone.national) : null,
          phone_country: values.phone.national ? values.phone.country : null,
        },
      });
      await queryClient.invalidateQueries({ queryKey: accountQueryKey() });
      toast({ title: 'Profile updated', variant: 'success' });
    } catch (error) {
      const applied = applyApiFieldErrors(error, { setError, fallbackField: 'first_name' });
      if (!applied.handled) toast({ title: errorMessage(error), variant: 'danger' });
    }
  });

  return (
    <form className="flex max-w-md flex-col gap-4" onSubmit={onSubmit} noValidate>
      <FormField label="First name" required error={errors.first_name?.message}>
        <Input autoComplete="given-name" {...register('first_name')} />
      </FormField>
      <FormField label="Last name" required error={errors.last_name?.message}>
        <Input autoComplete="family-name" {...register('last_name')} />
      </FormField>
      <FormField label="Phone" error={errors.phone?.message}>
        <Controller
          name="phone"
          control={control}
          render={({ field }) => (
            <PhoneInput value={field.value} onChange={field.onChange} onBlur={field.onBlur} />
          )}
        />
      </FormField>
      <div>
        <Button type="submit" disabled={mutation.isPending}>
          {mutation.isPending ? 'Saving…' : 'Save changes'}
        </Button>
      </div>
    </form>
  );
}
