import { zodResolver } from '@hookform/resolvers/zod';
import { useState } from 'react';
import { Controller, useForm } from 'react-hook-form';
import { useTranslation } from 'react-i18next';
import { Link, useLocation, useNavigate } from 'react-router-dom';
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
import { PortalAuthLayout } from '../../layouts/PortalAuthLayout';

const phoneSchema = z
  .object({ country: z.string(), national: z.string() })
  .refine(isValidPhoneValue, { message: 'auth.invalidPhone' });

const schema = z
  .object({
    first_name: z.string().min(1, 'auth.required'),
    last_name: z.string().min(1, 'auth.required'),
    email: z.string().email('auth.invalidEmail'),
    phone: phoneSchema,
    password: z.string().min(12, 'auth.passwordMin'),
    confirm: z.string(),
    accept_terms: z.boolean().refine((value) => value, { message: 'auth.required' }),
    accept_privacy: z.boolean().refine((value) => value, { message: 'auth.required' }),
  })
  .refine((values) => values.password === values.confirm, {
    path: ['confirm'],
    message: 'auth.required',
  });

type FormValues = z.infer<typeof schema>;

export function RegisterPage() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const location = useLocation();
  const from = (location.state as { from?: string } | null)?.from;
  const { refresh } = useCustomerAuth();
  const touchReservation = useReservationTouch();
  const registerMutation = useSportsCoachBookingsWebPortalAccountRegistrationsControllerCreate();
  const [documentKind, setDocumentKind] = useState<'terms' | 'privacy' | null>(null);

  const {
    register,
    handleSubmit,
    setError,
    control,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      accept_terms: false,
      accept_privacy: false,
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
      navigate(from ?? '/account', { replace: true });
    } catch (error) {
      applyApiFieldErrors(error, { setError });
    }
  });

  return (
    <PortalAuthLayout
      title={t('auth.registerTitle')}
      subtitle={t('auth.registerSubtitle')}
      footer={
        <span className="text-muted-foreground">
          {t('auth.alreadyHaveAccount')}{' '}
          <Link to="/login" state={{ from }} className="text-primary hover:underline">
            {t('common.signIn')}
          </Link>
        </span>
      }
    >
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
          <Input type="password" autoComplete="new-password" {...register('password')} />
        </FormField>
        <FormField
          label={t('auth.confirmPassword')}
          error={errors.confirm && t(errors.confirm.message ?? '')}
        >
          <Input type="password" autoComplete="new-password" {...register('confirm')} />
        </FormField>
        <Controller
          name="accept_terms"
          control={control}
          render={({ field }) => (
            <Checkbox
              label={
                <>
                  {t('auth.acceptTermsPrefix')}
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
                </>
              }
              checked={field.value}
              onCheckedChange={field.onChange}
            />
          )}
        />
        <Controller
          name="accept_privacy"
          control={control}
          render={({ field }) => (
            <Checkbox
              label={
                <>
                  {t('auth.acceptPrivacyPrefix')}
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
    </PortalAuthLayout>
  );
}
