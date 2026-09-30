import { zodResolver } from '@hookform/resolvers/zod';
import { useForm } from 'react-hook-form';
import { useTranslation } from 'react-i18next';
import { useNavigate, useParams } from 'react-router-dom';
import { z } from 'zod';
import {
  getSportsCoachBookingsWebStaffInvitesControllerShowQueryKey,
  useSportsCoachBookingsWebStaffInvitesControllerAccept,
  useSportsCoachBookingsWebStaffInvitesControllerShow,
} from '@scb/api-client';
import { Button, FormField, Input, Splash } from '@scb/ui';
import { useStaffAuth } from '../../auth/staff-auth';
import { AuthLayout } from '../../layouts/AuthLayout';

const schema = z.object({
  password: z.string().min(12, 'auth.passwordMin').or(z.literal('')),
});
type FormValues = z.infer<typeof schema>;

export function AcceptInvitePage() {
  const { t } = useTranslation();
  const { token = '' } = useParams();
  const navigate = useNavigate();
  const { status, refresh } = useStaffAuth();
  const isExistingUser = status === 'authenticated';

  const inviteQuery = useSportsCoachBookingsWebStaffInvitesControllerShow(token, {
    query: {
      queryKey: getSportsCoachBookingsWebStaffInvitesControllerShowQueryKey(token),
      enabled: Boolean(token),
    },
  });
  const invite = inviteQuery.data?.data as
    | {
        email: string;
        expired: boolean;
        role: string;
        tenant_name: string;
      }
    | undefined;
  const accept = useSportsCoachBookingsWebStaffInvitesControllerAccept();

  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { password: '' },
  });

  const onSubmit = handleSubmit(async ({ password }) => {
    await accept.mutateAsync({
      token,
      data: password ? { password } : {},
    });
    refresh();
    navigate('/', { replace: true });
  });

  if (inviteQuery.isLoading) return <Splash label="Loading invitation…" />;

  if (inviteQuery.isError || !invite) {
    return (
      <AuthLayout title={t('auth.inviteTitle')}>
        <p role="alert" className="text-sm text-danger">
          {t('auth.confirmFailed')}
        </p>
      </AuthLayout>
    );
  }

  return (
    <AuthLayout title={t('auth.inviteTitle')} subtitle={`${invite.tenant_name} · ${invite.role}`}>
      <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
        <p className="text-sm">
          {isExistingUser ? t('auth.inviteExistingUser') : t('auth.inviteNewUser')}
        </p>
        {!isExistingUser ? (
          <FormField
            label={t('auth.password')}
            error={errors.password && t(errors.password.message ?? '')}
          >
            <Input type="password" autoComplete="new-password" {...register('password')} />
          </FormField>
        ) : null}
        <Button type="submit" disabled={isSubmitting}>
          {t('auth.acceptInvite')}
        </Button>
      </form>
    </AuthLayout>
  );
}
