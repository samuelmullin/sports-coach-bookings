import { zodResolver } from '@hookform/resolvers/zod';
import { useForm } from 'react-hook-form';
import { useTranslation } from 'react-i18next';
import { Link } from 'react-router-dom';
import { z } from 'zod';
import { useSportsCoachBookingsWebPlatformPasswordResetControllerCreate } from '@scb/api-client';
import { Button, FormField, Input } from '@scb/ui';
import { AuthLayout } from '../../layouts/AuthLayout';

const schema = z.object({ email: z.string().email('auth.invalidEmail') });
type FormValues = z.infer<typeof schema>;

export function ForgotPasswordPage() {
  const { t } = useTranslation();
  const request = useSportsCoachBookingsWebPlatformPasswordResetControllerCreate();
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting, isSubmitSuccessful },
  } = useForm<FormValues>({ resolver: zodResolver(schema) });

  const onSubmit = handleSubmit(async (values) => {
    await request.mutateAsync({ data: values }).catch(() => undefined);
  });

  return (
    <AuthLayout
      title={t('auth.forgotTitle')}
      subtitle={t('auth.forgotSubtitle')}
      footer={
        <Link to="/login" className="text-primary hover:underline">
          {t('common.back')}
        </Link>
      }
    >
      {isSubmitSuccessful ? (
        <p role="status" className="text-sm text-foreground">
          {t('auth.resetSent')}
        </p>
      ) : (
        <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
          <FormField label={t('auth.email')} error={errors.email && t(errors.email.message ?? '')}>
            <Input type="email" autoComplete="email" {...register('email')} />
          </FormField>
          <Button type="submit" disabled={isSubmitting}>
            {t('auth.sendReset')}
          </Button>
        </form>
      )}
    </AuthLayout>
  );
}
