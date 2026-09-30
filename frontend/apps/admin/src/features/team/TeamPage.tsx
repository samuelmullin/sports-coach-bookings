import { useState } from 'react';
import { UserPlus } from 'lucide-react';
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  ConfirmDialog,
  EmptyState,
  Select,
  Table,
  useToast,
} from '@scb/ui';
import { useStaffAuth } from '../../auth/staff-auth';
import {
  useRemoveTeamMember,
  useTeam,
  useTeamInvites,
  useTransferOwnership,
  useUpdateTeamMember,
  type TeamInvite,
  type TeamMember,
} from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';
import { InviteMemberDialog } from './InviteMemberDialog';

export function TeamPage() {
  const { role: currentRole, membership } = useStaffAuth();
  const teamQuery = useTeam();
  const invitesQuery = useTeamInvites();
  const updateMember = useUpdateTeamMember();
  const removeMember = useRemoveTeamMember();
  const transferOwnership = useTransferOwnership();
  const { toast } = useToast();

  const [inviteOpen, setInviteOpen] = useState(false);
  const [pendingRemove, setPendingRemove] = useState<TeamMember | null>(null);
  const [pendingTransfer, setPendingTransfer] = useState<TeamMember | null>(null);

  const members = listItems<TeamMember>(teamQuery);
  const invites = listItems<TeamInvite>(invitesQuery);
  const isOwner = currentRole === 'owner';

  const changeRole = async (member: TeamMember, nextRole: string) => {
    if (!member.id) return;
    try {
      await updateMember.mutateAsync({ id: member.id, data: { role: nextRole as never } });
      toast({ title: 'Role updated', variant: 'success' });
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    }
  };

  const confirmRemove = async () => {
    if (!pendingRemove?.id) return;
    try {
      await removeMember.mutateAsync({ id: pendingRemove.id });
      toast({ title: 'Team member removed', variant: 'success' });
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    } finally {
      setPendingRemove(null);
    }
  };

  const confirmTransfer = async () => {
    if (!pendingTransfer?.id) return;
    try {
      await transferOwnership.mutateAsync({ data: { membership_id: pendingTransfer.id } });
      toast({ title: 'Ownership transferred', variant: 'success' });
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    } finally {
      setPendingTransfer(null);
    }
  };

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title="Team"
        description="Manage who can access your business and what they can do."
        actions={
          <Button onClick={() => setInviteOpen(true)}>
            <UserPlus className="h-4 w-4" aria-hidden="true" />
            Invite member
          </Button>
        }
      />

      <QueryState
        loading={teamQuery.isLoading}
        error={teamQuery.isError ? errorMessage(teamQuery.error) : undefined}
        onRetry={() => void teamQuery.refetch()}
      >
        {members.length === 0 ? (
          <EmptyState
            title="No team members yet"
            description="Invite a coach or admin to get started."
          />
        ) : (
          <Card>
            <CardHeader>
              <CardTitle>Members</CardTitle>
            </CardHeader>
            <CardContent>
              <Table
                caption="Team members"
                rowKey={(row) => row.id ?? row.staff_user_id ?? ''}
                columns={[
                  {
                    key: 'name',
                    header: 'Name',
                    cell: (row) => (
                      <span className="font-medium">
                        {row.display_name || row.staff_user?.email || 'Unnamed'}
                      </span>
                    ),
                  },
                  { key: 'email', header: 'Email', cell: (row) => row.staff_user?.email ?? '—' },
                  {
                    key: 'role',
                    header: 'Role',
                    cell: (row) => (
                      <Select
                        aria-label={`Role for ${row.staff_user?.email ?? row.id}`}
                        className="h-8 w-28"
                        value={row.role ?? 'coach'}
                        disabled={!isOwner && row.role === 'owner'}
                        onValueChange={(value) => void changeRole(row, value)}
                        options={[
                          { value: 'coach', label: 'Coach' },
                          { value: 'admin', label: 'Admin' },
                          { value: 'owner', label: 'Owner' },
                        ]}
                      />
                    ),
                  },
                  {
                    key: 'status',
                    header: 'Status',
                    cell: (row) => (
                      <Badge variant={row.status === 'active' ? 'success' : 'outline'}>
                        {row.status ?? 'invited'}
                      </Badge>
                    ),
                  },
                  {
                    key: 'actions',
                    header: '',
                    align: 'right',
                    cell: (row) => (
                      <div className="flex justify-end gap-1">
                        {isOwner && row.id && row.id !== membership?.id ? (
                          <Button variant="ghost" size="sm" onClick={() => setPendingTransfer(row)}>
                            Make owner
                          </Button>
                        ) : null}
                        {row.id !== membership?.id ? (
                          <Button variant="ghost" size="sm" onClick={() => setPendingRemove(row)}>
                            Remove
                          </Button>
                        ) : null}
                      </div>
                    ),
                  },
                ]}
                data={members}
              />
            </CardContent>
          </Card>
        )}
      </QueryState>

      <Card>
        <CardHeader>
          <CardTitle>Pending invitations</CardTitle>
        </CardHeader>
        <CardContent>
          {invites.length === 0 ? (
            <p className="text-sm text-muted-foreground">No pending invitations.</p>
          ) : (
            <Table
              caption="Pending invitations"
              rowKey={(row) => row.id ?? row.email ?? ''}
              columns={[
                { key: 'email', header: 'Email', cell: (row) => row.email },
                { key: 'role', header: 'Role', cell: (row) => row.role },
                {
                  key: 'expires',
                  header: 'Expires',
                  cell: (row) =>
                    row.expires_at ? new Date(row.expires_at).toLocaleDateString() : '—',
                },
              ]}
              data={invites}
            />
          )}
        </CardContent>
      </Card>

      <InviteMemberDialog open={inviteOpen} onOpenChange={setInviteOpen} />

      <ConfirmDialog
        open={pendingRemove !== null}
        onOpenChange={(open) => !open && setPendingRemove(null)}
        title="Remove team member?"
        description={`${pendingRemove?.display_name ?? pendingRemove?.staff_user?.email ?? 'This member'} will immediately lose access to this business.`}
        confirmLabel="Remove"
        destructive
        loading={removeMember.isPending}
        onConfirm={() => void confirmRemove()}
      />

      <ConfirmDialog
        open={pendingTransfer !== null}
        onOpenChange={(open) => !open && setPendingTransfer(null)}
        title="Transfer ownership?"
        description="The selected member becomes the owner and you will be downgraded to admin. This cannot be undone by you."
        confirmLabel="Transfer ownership"
        destructive
        loading={transferOwnership.isPending}
        onConfirm={() => void confirmTransfer()}
      />
    </div>
  );
}
