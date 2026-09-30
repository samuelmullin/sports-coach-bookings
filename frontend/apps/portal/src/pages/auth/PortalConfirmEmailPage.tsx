import { useEffect, useRef } from 'react';
import { useTranslation } from 'react-i18next';
import { Link, useSearchParams } from 'react-router-dom';
import { useSportsCoachBookingsWebPortalAccountConfirmationsControllerCreate } from '@scb/api-client';
import { Splash } from '@scb/ui';
import { PortalAuthLayout } from '../../layouts/PortalAuthLayout';

export function PortalConfirmEmailPage() {
  const { t } = useTranslation();
  const [searchParams] = useSearchParams();
  const token = searchParams.get('token') ?? '';
  const confirm = useSportsCoachBookingsWebPortalAccountConfirmationsControllerCreate();
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
      <PortalAuthLayout title={t('auth.confirmTitle')}>
        <p role="alert" className="text-sm text-danger">
          {t('auth.confirmFailed')}
        </p>
      </PortalAuthLayout>
    );
  }

  if (confirm.isPending) return <Splash label={t('auth.confirmBody')} />;

  return (
    <PortalAuthLayout title={t('auth.confirmTitle')}>
      {confirm.isSuccess ? (
        <div className="flex flex-col gap-3">
          <p role="status" className="text-sm">
            {t('auth.confirmDone')}
          </p>
          <Link to="/login" className="text-sm text-primary hover:underline">
            {t('common.signIn')}
          </Link>
        </div>
      ) : (
        <p role="alert" className="text-sm text-danger">
          {t('auth.confirmFailed')}
        </p>
      )}
    </PortalAuthLayout>
  );
}
