import { Link } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { Button, EmptyState } from '@scb/ui';
import { ShieldAlert } from 'lucide-react';

export function ForbiddenPage() {
  const { t } = useTranslation();
  return (
    <EmptyState
      icon={<ShieldAlert className="h-8 w-8" />}
      title={t('common.forbiddenTitle')}
      description={t('common.forbiddenBody')}
      action={
        <Button asChild variant="outline">
          <Link to="/">{t('common.back')}</Link>
        </Button>
      }
    />
  );
}
