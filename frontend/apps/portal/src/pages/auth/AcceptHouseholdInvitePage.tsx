import { zodResolver } from '@hookform/resolvers/zod';
import { useForm } from 'react-hook-form';
import { useTranslation } from 'react-i18next';
import { useNavigate, useParams } from 'react-router-dom';
import { z } from 'zod';
import {
  getSportsCoachBookingsWebPortalHouseholdInvitesControllerShowQueryKey,
  useSportsCoachBookingsWebPortalHouseholdInvitesControllerAccept,
  useSportsCoachBookingsWebPortalHouseholdInvitesControllerShow,
} from '@scb/api-client';
import { Button, FormField, Input, Splash } from '@scb/ui';
import { useCustomerAuth } from '../../auth/customer-auth';
import { PortalAuthLayout } from '../../layouts/PortalAuthLayout';

const schema = z.object({
  first_name: z.string().min(1, 'auth.required').or(z.literal('')),
  last_name: z.string().min(1, 'auth.required').or(z.literal('')),
  password: z.string().min(12, 'auth.passwordMin').or(z.literal('')),
});
type FormValues = z.infer<typeof schema>;

export function AcceptHouseholdInvitePage() {
  const { t } = useTranslation();
  const { token = '' } = useParams();
  const navigate = useNavigate();
  const { status, refresh } = useCustomerAuth();
  const isExistingUser = status === 'authenticated';

  const inviteQuery = useSportsCoachBookingsWebPortalHouseholdInvitesControllerShow(token, {
    query: {
      queryKey: getSportsCoachBookingsWebPortalHouseholdInvitesControllerShowQueryKey(token),
      enabled: Boolean(token),
    },
  });
  const invite = inviteQuery.data?.data as
    | {
        email: string;
        expired: boolean;
        relationship: string | null;
        tenant_name: string;
      }
    | undefined;

  const accept = useSportsCoachBookingsWebPortalHouseholdInvitesControllerAccept();

  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({ resolver: zodResolver(schema) });

  const onSubmit = handleSubmit(async (values) => {
    await accept.mutateAsync({
      token,
      data: {
        ...(isExistingUser
          ? {}
          : {
              first_name: values.first_name,
              last_name: values.last_name,
              password: values.password,
              accept_terms: true,
              accept_privacy: true,
            }),
      },
    });
    refresh();
    navigate('/household', { replace: true });
  });

  if (inviteQuery.isLoading) return <Splash label="Loading invitation…" />;

  if (inviteQuery.isError || !invite) {
    return (
      <PortalAuthLayout title={t('auth.inviteTitle')}>
        <p role="alert" className="text-sm text-danger">
          {t('auth.confirmFailed')}
        </p>
      </PortalAuthLayout>
    );
  }

  return (
    <PortalAuthLayout
      title={t('auth.inviteTitle')}
      subtitle={`${invite.tenant_name} · ${invite.relationship ?? ''}`}
    >
      <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
        {!isExistingUser ? (
          <>
            <div className="grid grid-cols-2 gap-3">
              <FormField
                label={t('auth.firstName')}
                error={errors.first_name && t(errors.first_name.message ?? '')}
              >
                <Input {...register('first_name')} />
              </FormField>
              <FormField
                label={t('auth.lastName')}
                error={errors.last_name && t(errors.last_name.message ?? '')}
              >
                <Input {...register('last_name')} />
              </FormField>
            </div>
            <FormField
              label={t('auth.password')}
              error={errors.password && t(errors.password.message ?? '')}
            >
              <Input type="password" autoComplete="new-password" {...register('password')} />
            </FormField>
          </>
        ) : null}
        <Button type="submit" disabled={isSubmitting}>
          {t('auth.acceptInvite')}
        </Button>
      </form>
    </PortalAuthLayout>
  );
}
