import { zodResolver } from '@hookform/resolvers/zod';
import { useForm } from 'react-hook-form';
import { useTranslation } from 'react-i18next';
import { Link, useSearchParams } from 'react-router-dom';
import { z } from 'zod';
import { useSportsCoachBookingsWebPortalAccountPasswordResetControllerUpdate } from '@scb/api-client';
import { Button, FormField, Input } from '@scb/ui';
import { PortalAuthLayout } from '../../layouts/PortalAuthLayout';

const schema = z
  .object({
    password: z.string().min(12, 'auth.passwordMin'),
    confirm: z.string(),
  })
  .refine((values) => values.password === values.confirm, {
    path: ['confirm'],
    message: 'auth.required',
  });

type FormValues = z.infer<typeof schema>;

export function PortalResetPasswordPage() {
  const { t } = useTranslation();
  const [searchParams] = useSearchParams();
  const token = searchParams.get('token') ?? '';
  const reset = useSportsCoachBookingsWebPortalAccountPasswordResetControllerUpdate();
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting, isSubmitSuccessful },
  } = useForm<FormValues>({ resolver: zodResolver(schema) });

  const onSubmit = handleSubmit(async ({ password }) => {
    await reset.mutateAsync({ data: { token, password } });
  });

  return (
    <PortalAuthLayout title={t('auth.resetTitle')}>
      {isSubmitSuccessful ? (
        <div className="flex flex-col gap-3">
          <p role="status" className="text-sm">
            {t('auth.resetDone')}
          </p>
          <Link to="/login" className="text-sm text-primary hover:underline">
            {t('common.signIn')}
          </Link>
        </div>
      ) : (
        <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
          <FormField
            label={t('auth.newPassword')}
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
          <Button type="submit" disabled={isSubmitting || !token}>
            {t('auth.resetPassword')}
          </Button>
        </form>
      )}
    </PortalAuthLayout>
  );
}
