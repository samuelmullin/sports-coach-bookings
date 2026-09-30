import { zodResolver } from '@hookform/resolvers/zod';
import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { useTranslation } from 'react-i18next';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { z } from 'zod';
import {
  applyApiFieldErrors,
  useSportsCoachBookingsWebPortalAccountSessionControllerCreate,
} from '@scb/api-client';
import { Button, FormField, Input } from '@scb/ui';
import { useCustomerAuth } from '../../auth/customer-auth';
import { useReservationTouch } from '../../features/reservations/useReservationTouch';
import { PortalAuthLayout } from '../../layouts/PortalAuthLayout';

const schema = z.object({
  email: z.string().email('auth.invalidEmail'),
  password: z.string().min(1, 'auth.required'),
});
type FormValues = z.infer<typeof schema>;

export function PortalLoginPage() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const location = useLocation();
  const { refresh } = useCustomerAuth();
  const touchReservation = useReservationTouch();
  const from = (location.state as { from?: string } | null)?.from;
  const [formError, setFormError] = useState<string | null>(null);
  const login = useSportsCoachBookingsWebPortalAccountSessionControllerCreate();

  const {
    register,
    handleSubmit,
    setError,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({ resolver: zodResolver(schema) });

  const onSubmit = handleSubmit(async (values) => {
    setFormError(null);
    try {
      await login.mutateAsync({ data: values });
      await touchReservation();
      refresh();
      navigate(from ?? '/account', { replace: true });
    } catch (error) {
      const applied = applyApiFieldErrors(error, {
        setError,
        fallbackField: 'password',
      });
      if (!applied.handled) setFormError(t('auth.invalidCredentials'));
    }
  });

  return (
    <PortalAuthLayout
      title={t('auth.loginTitle')}
      subtitle={t('auth.loginSubtitle')}
      footer={
        <span className="text-muted-foreground">
          {t('auth.noAccount')}{' '}
          <Link to="/register" state={{ from }} className="text-primary hover:underline">
            {t('common.register')}
          </Link>
        </span>
      }
    >
      <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
        <FormField label={t('auth.email')} error={errors.email && t(errors.email.message ?? '')}>
          <Input type="email" autoComplete="email" {...register('email')} />
        </FormField>
        <FormField
          label={t('auth.password')}
          error={errors.password && t(errors.password.message ?? '')}
        >
          <Input type="password" autoComplete="current-password" {...register('password')} />
        </FormField>
        {formError ? (
          <p role="alert" className="text-sm font-medium text-danger">
            {formError}
          </p>
        ) : null}
        <Button type="submit" disabled={isSubmitting}>
          {t('auth.signIn')}
        </Button>
        <Link to="/forgot-password" className="text-center text-sm text-primary hover:underline">
          {t('auth.forgotPassword')}
        </Link>
      </form>
    </PortalAuthLayout>
  );
}
