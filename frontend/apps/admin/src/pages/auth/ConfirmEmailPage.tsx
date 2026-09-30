import { useEffect, useRef } from 'react';
import { useTranslation } from 'react-i18next';
import { Link, useSearchParams } from 'react-router-dom';
import { useSportsCoachBookingsWebPlatformRegistrationControllerConfirm } from '@scb/api-client';
import { Splash } from '@scb/ui';
import { AuthLayout } from '../../layouts/AuthLayout';

export function ConfirmEmailPage() {
  const { t } = useTranslation();
  const [searchParams] = useSearchParams();
  const token = searchParams.get('token') ?? '';
  const confirm = useSportsCoachBookingsWebPlatformRegistrationControllerConfirm();
  const started = useRef(false);

  useEffect(() => {
    if (started.current) return;
    started.current = true;
    if (token) {
      void confirm.mutateAsync({ data: { token } }).catch(() => undefined);
    }
  }, [confirm, token]);

  if (!token) {
    return (
      <AuthLayout title={t('auth.confirmTitle')}>
        <p role="alert" className="text-sm text-danger">
          {t('auth.confirmFailed')}
        </p>
      </AuthLayout>
    );
  }

  if (confirm.isPending) {
    return <Splash label={t('auth.confirmBody')} />;
  }

  return (
    <AuthLayout title={t('auth.confirmTitle')}>
      {confirm.isSuccess ? (
        <div className="flex flex-col gap-3">
          <p role="status" className="text-sm text-foreground">
            {t('auth.confirmDone')}
          </p>
          <Link to="/login" className="text-sm text-primary hover:underline">
            {t('auth.signIn')}
          </Link>
        </div>
      ) : (
        <p role="alert" className="text-sm text-danger">
          {t('auth.confirmFailed')}
        </p>
      )}
    </AuthLayout>
  );
}
