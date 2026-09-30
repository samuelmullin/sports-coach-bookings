import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { TabsView } from '@scb/ui';
import { useAccount, type Account, type CustomerUser } from '../../api/endpoints';
import { body } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { ProfileForm } from './ProfileForm';
import { EmailForm } from './EmailForm';
import { PasswordForm } from './PasswordForm';
import { NotificationPreferencesForm } from './NotificationPreferencesForm';
import { useCustomerAuth } from '../../auth/customer-auth';

export function AccountPage() {
  const { t } = useTranslation();
  const { customerUser: authUser } = useCustomerAuth();
  const query = useAccount();
  const account = body<Account>(query);
  const customerUser: CustomerUser | undefined = account?.customer_user ?? authUser;

  const [tab, setTab] = useState('profile');

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title={t('account.title')}
        description={
          customerUser ? `${customerUser.first_name} ${customerUser.last_name}` : undefined
        }
      />
      <TabsView
        aria-label="Account sections"
        value={tab}
        onValueChange={setTab}
        items={[
          {
            value: 'profile',
            label: 'Profile',
            content: <ProfileForm customerUser={customerUser} />,
          },
          { value: 'email', label: 'Email', content: <EmailForm customerUser={customerUser} /> },
          { value: 'password', label: 'Password', content: <PasswordForm /> },
          {
            value: 'notifications',
            label: 'Notifications',
            content: <NotificationPreferencesForm />,
          },
        ]}
      />
    </div>
  );
}
