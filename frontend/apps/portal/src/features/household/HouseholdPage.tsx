import { useState } from 'react';
import { useTranslation } from 'react-i18next';
import { LogOut, Plus, UserMinus, Users } from 'lucide-react';
import { Badge, Button, Card, CardContent, ConfirmDialog, EmptyState, useToast } from '@scb/ui';
import { useQueryClient } from '@tanstack/react-query';
import {
  householdInvitesQueryKey,
  householdQueryKey,
  useHousehold,
  useHouseholdInvites,
  useLeaveHousehold,
  useRemoveHouseholdMember,
  useTransferPrimary,
  type Household,
  type HouseholdInvite,
  type HouseholdMember,
} from '../../api/endpoints';
import { body, errorMessage, listItems } from '../shared/api-utils';
import { QueryState } from '../shared/QueryState';
import { PageHeader } from '../shared/PageHeader';
import { useCustomerAuth } from '../../auth/customer-auth';
import { InviteMemberDialog } from './InviteMemberDialog';

export function HouseholdPage() {
  const { t } = useTranslation();
  const { customerUser, signOut } = useCustomerAuth();
  const query = useHousehold();
  const invitesQuery = useHouseholdInvites();
  const removeMember = useRemoveHouseholdMember();
  const transfer = useTransferPrimary();
  const leave = useLeaveHousehold();
  const queryClient = useQueryClient();
  const { toast } = useToast();

  const [inviteOpen, setInviteOpen] = useState(false);
  const [pendingRemove, setPendingRemove] = useState<HouseholdMember | null>(null);
  const [pendingTransfer, setPendingTransfer] = useState<HouseholdMember | null>(null);
  const [leaveOpen, setLeaveOpen] = useState(false);

  const household = body<Household>(query);
  const members = household?.members ?? [];
  const invites = listItems<HouseholdInvite>(invitesQuery);
  const currentMember = members.find((member) => member.customer_user?.id === customerUser?.id);
  const isPrimary = currentMember?.role === 'primary';

  const refresh = () =>
    Promise.all([
      queryClient.invalidateQueries({ queryKey: householdQueryKey() }),
      queryClient.invalidateQueries({ queryKey: householdInvitesQueryKey() }),
    ]);

  const confirmRemove = async () => {
    if (!pendingRemove) return;
    try {
      await removeMember.mutateAsync({ id: pendingRemove.id ?? '' });
      await refresh();
      toast({ title: 'Member removed', variant: 'success' });
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    } finally {
      setPendingRemove(null);
    }
  };

  const confirmTransfer = async () => {
    if (!pendingTransfer) return;
    try {
      await transfer.mutateAsync({ data: { member_id: pendingTransfer.id ?? '' } });
      await refresh();
      toast({ title: 'Primary contact transferred', variant: 'success' });
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    } finally {
      setPendingTransfer(null);
    }
  };

  const confirmLeave = async () => {
    try {
      await leave.mutateAsync();
      toast({ title: 'You left the household', variant: 'success' });
      await signOut();
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    } finally {
      setLeaveOpen(false);
    }
  };

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title={t('nav.household')}
        description="Adults who can manage players, bookings and payments."
        actions={
          <Button onClick={() => setInviteOpen(true)}>
            <Plus className="h-4 w-4" aria-hidden="true" /> Invite adult
          </Button>
        }
      />

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {members.length === 0 ? (
          <EmptyState icon={<Users className="h-8 w-8" />} title={t('empty.household')} />
        ) : (
          <ul className="flex flex-col gap-3">
            {members.map((member) => {
              const isSelf = member.customer_user?.id === customerUser?.id;
              return (
                <li key={member.id}>
                  <Card>
                    <CardContent className="flex flex-wrap items-center justify-between gap-3 pt-4">
                      <div className="flex flex-col gap-0.5">
                        <span className="font-medium">
                          {member.customer_user?.first_name} {member.customer_user?.last_name}
                          {isSelf ? ' (you)' : ''}
                        </span>
                        <span className="text-sm text-muted-foreground">
                          {member.customer_user?.email}
                        </span>
                        {member.relationship ? (
                          <span className="text-xs text-muted-foreground">
                            {member.relationship}
                          </span>
                        ) : null}
                      </div>
                      <div className="flex flex-wrap items-center gap-2">
                        <Badge variant={member.role === 'primary' ? 'default' : 'outline'}>
                          {member.role === 'primary' ? 'Primary' : 'Manager'}
                        </Badge>
                        {isPrimary && !isSelf && member.role !== 'primary' ? (
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={() => setPendingTransfer(member)}
                          >
                            Make primary
                          </Button>
                        ) : null}
                        {isPrimary && !isSelf ? (
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={() => setPendingRemove(member)}
                          >
                            <UserMinus className="h-4 w-4" aria-hidden="true" /> Remove
                          </Button>
                        ) : null}
                      </div>
                    </CardContent>
                  </Card>
                </li>
              );
            })}
          </ul>
        )}

        {invites.length > 0 ? (
          <div className="flex flex-col gap-2">
            <h2 className="text-sm font-medium">Pending invitations</h2>
            <ul className="flex flex-col gap-2">
              {invites.map((invite) => (
                <li
                  key={invite.id}
                  className="flex items-center justify-between rounded-md border border-dashed border-border p-3 text-sm"
                >
                  <span>{invite.email}</span>
                  <Badge variant="warning">Pending</Badge>
                </li>
              ))}
            </ul>
          </div>
        ) : null}

        <div>
          <Button variant="outline" onClick={() => setLeaveOpen(true)}>
            <LogOut className="h-4 w-4" aria-hidden="true" /> Leave household
          </Button>
        </div>
      </QueryState>

      <InviteMemberDialog open={inviteOpen} onOpenChange={setInviteOpen} />

      <ConfirmDialog
        open={pendingRemove !== null}
        onOpenChange={(open) => !open && setPendingRemove(null)}
        title="Remove this member?"
        description={`${pendingRemove?.customer_user?.first_name ?? 'This person'} will lose access to the household.`}
        confirmLabel="Remove"
        destructive
        loading={removeMember.isPending}
        onConfirm={() => void confirmRemove()}
      />

      <ConfirmDialog
        open={pendingTransfer !== null}
        onOpenChange={(open) => !open && setPendingTransfer(null)}
        title="Transfer primary contact?"
        description="The primary contact is responsible for the household. You will remain a manager."
        confirmLabel="Transfer"
        loading={transfer.isPending}
        onConfirm={() => void confirmTransfer()}
      />

      <ConfirmDialog
        open={leaveOpen}
        onOpenChange={setLeaveOpen}
        title="Leave household?"
        description="You will lose access to this household's players, bookings and sessions."
        confirmLabel="Leave"
        destructive
        loading={leave.isPending}
        onConfirm={() => void confirmLeave()}
      />
    </div>
  );
}
