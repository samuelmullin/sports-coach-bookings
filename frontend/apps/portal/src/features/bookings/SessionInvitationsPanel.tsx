import { Badge, Button, Card, CardContent, useToast } from '@scb/ui';
import {
  useCancelSessionInvitation,
  useHousehold,
  useResendSessionInvitation,
  useSessionInvitations,
  type SessionInvitation,
} from '../../api/endpoints';
import { errorMessage, listItems, responseData } from '../shared/api-utils';
import { QueryState } from '../shared/QueryState';

const STATUS_VARIANT: Record<string, 'success' | 'warning' | 'outline' | 'danger'> = {
  pending: 'warning',
  accepted: 'success',
  expired: 'outline',
  cancelled: 'outline',
  declined: 'danger',
};

export function SessionInvitationsPanel() {
  const query = useSessionInvitations();
  const householdQuery = useHousehold();
  const cancel = useCancelSessionInvitation();
  const resend = useResendSessionInvitation();
  const { toast } = useToast();
  const invitations = listItems<SessionInvitation>(query);
  const household = responseData<{ id?: string }>(householdQuery.data);

  const act = async (kind: 'cancel' | 'resend', invitation: SessionInvitation) => {
    try {
      if (kind === 'cancel') await cancel.mutateAsync({ id: invitation.id });
      else await resend.mutateAsync({ id: invitation.id });
      toast({
        title: kind === 'cancel' ? 'Invitation cancelled' : 'Invitation resent',
        variant: 'success',
      });
      await query.refetch();
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    }
  };

  return (
    <section className="flex flex-col gap-3" aria-labelledby="session-invitations-heading">
      <div>
        <h2 id="session-invitations-heading" className="text-lg font-semibold">
          Session invitations
        </h2>
        <p className="text-sm text-muted-foreground">Track invitations you sent or accepted.</p>
      </div>
      <QueryState
        loading={query.isLoading || householdQuery.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {invitations.length === 0 ? (
          <p className="text-sm text-muted-foreground">No session invitations yet.</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {invitations.map((invitation) => {
              const outgoing = invitation.organizer_household_id === household?.id;
              const pendingOutgoing = outgoing && invitation.status === 'pending';
              return (
                <li key={invitation.id}>
                  <Card>
                    <CardContent className="flex flex-wrap items-center justify-between gap-3 pt-4">
                      <div className="flex flex-col gap-1">
                        <div className="flex flex-wrap items-center gap-2">
                          <span className="font-medium">
                            {outgoing
                              ? `To ${invitation.email}`
                              : `Invitation for ${invitation.email}`}
                          </span>
                          <Badge variant={STATUS_VARIANT[invitation.status] ?? 'outline'}>
                            {invitation.status}
                          </Badge>
                        </div>
                        <span className="text-sm text-muted-foreground">
                          {invitation.payment_mode === 'organizer'
                            ? 'Organizer-funded space'
                            : 'Split payment'}
                          {invitation.expires_at
                            ? ` · expires ${new Date(invitation.expires_at).toLocaleString()}`
                            : ''}
                        </span>
                      </div>
                      {pendingOutgoing ? (
                        <div className="flex gap-2">
                          <Button
                            size="sm"
                            variant="outline"
                            disabled={resend.isPending || cancel.isPending}
                            onClick={() => void act('resend', invitation)}
                          >
                            Resend
                          </Button>
                          <Button
                            size="sm"
                            variant="ghost"
                            className="text-danger"
                            disabled={resend.isPending || cancel.isPending}
                            onClick={() => void act('cancel', invitation)}
                          >
                            Revoke
                          </Button>
                        </div>
                      ) : null}
                    </CardContent>
                  </Card>
                </li>
              );
            })}
          </ul>
        )}
      </QueryState>
    </section>
  );
}
