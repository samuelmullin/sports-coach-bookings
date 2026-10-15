import { zodResolver } from '@hookform/resolvers/zod';
import { useState } from 'react';
import { Controller, useForm } from 'react-hook-form';
import { useTranslation } from 'react-i18next';
import { z } from 'zod';
import {
  applyApiFieldErrors,
  useSportsCoachBookingsWebPortalAccountRegistrationsControllerCreate,
} from '@scb/api-client';
import {
  Button,
  Checkbox,
  FormField,
  Input,
  PhoneInput,
  isValidPhoneValue,
  phoneDigits,
  defaultPhoneCountry,
} from '@scb/ui';
import { useCustomerAuth } from '../../auth/customer-auth';
import { DocumentModal } from '../../features/shared/DocumentModal';
import { useReservationTouch } from '../../features/reservations/useReservationTouch';

const phoneSchema = z
  .object({ country: z.string(), national: z.string() })
  .refine(isValidPhoneValue, { message: 'auth.invalidPhone' });

const schema = z.object({
  first_name: z.string().min(1, 'auth.required'),
  last_name: z.string().min(1, 'auth.required'),
  email: z.string().email('auth.invalidEmail'),
  phone: phoneSchema,
  password: z.string().min(12, 'auth.passwordMin'),
  accept: z.boolean().refine((value) => value, { message: 'auth.required' }),
});

type FormValues = z.infer<typeof schema>;

export function RegisterForm({ onRegistered }: { onRegistered: () => void }) {
  const { t } = useTranslation();
  const { refresh } = useCustomerAuth();
  const touchReservation = useReservationTouch();
  const registerMutation = useSportsCoachBookingsWebPortalAccountRegistrationsControllerCreate();
  const [documentKind, setDocumentKind] = useState<'terms' | 'privacy' | null>(null);
  const [showPassword, setShowPassword] = useState(false);

  const {
    register,
    handleSubmit,
    setError,
    control,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      accept: false,
      phone: { country: defaultPhoneCountry, national: '' },
    },
  });

  const onSubmit = handleSubmit(async (values) => {
    try {
      await registerMutation.mutateAsync({
        data: {
          first_name: values.first_name,
          last_name: values.last_name,
          email: values.email,
          phone: values.phone.national ? phoneDigits(values.phone.national) : null,
          phone_country: values.phone.national ? values.phone.country : null,
          password: values.password,
          accept_terms: true,
          accept_privacy: true,
        },
      });
      await touchReservation();
      refresh();
      onRegistered();
    } catch (error) {
      applyApiFieldErrors(error, { setError });
    }
  });

  return (
    <>
      <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
        <div className="grid grid-cols-2 gap-3">
          <FormField
            label={t('auth.firstName')}
            error={errors.first_name && t(errors.first_name.message ?? '')}
          >
            <Input {...register('first_name')} />
          </FormField>
          <FormField
            label={t('auth.lastName')}
            error={errors.last_name && t(errors.last_name.message ?? '')}
          >
            <Input {...register('last_name')} />
          </FormField>
        </div>
        <FormField label={t('auth.email')} error={errors.email && t(errors.email.message ?? '')}>
          <Input type="email" autoComplete="email" {...register('email')} />
        </FormField>
        <FormField label={t('auth.phone')} error={errors.phone && t(errors.phone.message ?? '')}>
          <Controller
            name="phone"
            control={control}
            render={({ field }) => (
              <PhoneInput value={field.value} onChange={field.onChange} onBlur={field.onBlur} />
            )}
          />
        </FormField>
        <FormField
          label={t('auth.password')}
          error={errors.password && t(errors.password.message ?? '')}
        >
          <Input
            type={showPassword ? 'text' : 'password'}
            autoComplete="new-password"
            {...register('password')}
          />
        </FormField>
        <Checkbox
          label={t('auth.showPassword')}
          checked={showPassword}
          onCheckedChange={(checked) => setShowPassword(checked === true)}
        />
        <Controller
          name="accept"
          control={control}
          render={({ field }) => (
            <Checkbox
              label={
                <>
                  {t('auth.acceptPrefix')}
                  <a
                    href="#terms"
                    className="text-primary hover:underline"
                    onClick={(event) => {
                      event.preventDefault();
                      setDocumentKind('terms');
                    }}
                  >
                    {t('auth.termsLink')}
                  </a>
                  {t('auth.acceptJoin')}
                  <a
                    href="#privacy"
                    className="text-primary hover:underline"
                    onClick={(event) => {
                      event.preventDefault();
                      setDocumentKind('privacy');
                    }}
                  >
                    {t('auth.privacyLink')}
                  </a>
                </>
              }
              checked={field.value}
              onCheckedChange={field.onChange}
            />
          )}
        />
        <Button type="submit" disabled={isSubmitting}>
          {t('auth.createAccount')}
        </Button>
      </form>
      <DocumentModal
        open={documentKind !== null}
        onOpenChange={(open) => {
          if (!open) setDocumentKind(null);
        }}
        source={documentKind ? { type: 'legal', kind: documentKind } : null}
      />
    </>
  );
}
