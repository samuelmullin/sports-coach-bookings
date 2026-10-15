import { Link, useLocation, useNavigate } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { PortalAuthLayout } from '../../layouts/PortalAuthLayout';
import { RegisterForm } from './RegisterForm';

export function RegisterPage() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const location = useLocation();
  const from = (location.state as { from?: string } | null)?.from;

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
      <RegisterForm onRegistered={() => navigate(from ?? '/account', { replace: true })} />
    </PortalAuthLayout>
  );
}
