import { Link } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { Button, EmptyState } from '@scb/ui';

export function NotFoundPage() {
  const { t } = useTranslation();
  return (
    <EmptyState
      title={t('common.notFoundTitle')}
      description="The page you requested does not exist."
      action={
        <Button asChild variant="outline">
          <Link to="/">{t('common.back')}</Link>
        </Button>
      }
    />
  );
}
