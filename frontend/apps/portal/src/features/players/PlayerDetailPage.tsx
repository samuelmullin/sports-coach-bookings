import { useState } from 'react';
import { Link, useParams, useSearchParams } from 'react-router-dom';
import { useNavigate } from 'react-router-dom';
import { ArrowLeft, Archive } from 'lucide-react';
import { useQueryClient } from '@tanstack/react-query';
import { Badge, Button, ConfirmDialog, TabsView, useToast } from '@scb/ui';
import {
  playersQueryKey,
  playerQueryKey,
  useArchivePlayer,
  usePlayer,
  type PlayerResponse,
} from '../../api/endpoints';
import { body, errorMessage } from '../shared/api-utils';
import { QueryState } from '../shared/QueryState';
import { PageHeader } from '../shared/PageHeader';
import { readReturnTo } from '../shared/return-to';
import { usePortalSettings } from '../shared/extras';
import { PlayerBasicsForm, PlayerProfileForm } from './PlayerProfileSection';
import { EmergencyContactsSection } from './EmergencyContactsSection';
import { AuthorizedPickupsSection } from './AuthorizedPickupsSection';
import { MedicalSection } from './MedicalSection';
import { PlayerWaiversSection } from './PlayerWaiversSection';
import { FeedbackSection } from './FeedbackSection';

export function PlayerDetailPage() {
  const { playerId = '' } = useParams<{ playerId: string }>();
  const [searchParams, setSearchParams] = useSearchParams();
  const tab = searchParams.get('tab') ?? 'profile';
  const navigate = useNavigate();
  const returnTo = readReturnTo();
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const settings = usePortalSettings();
  const query = usePlayer(playerId, {
    query: { queryKey: playerQueryKey(playerId), enabled: Boolean(playerId), retry: false },
  });
  const player = body<PlayerResponse>(query);
  const archive = useArchivePlayer();
  const [archiveOpen, setArchiveOpen] = useState(false);

  const confirmArchive = async () => {
    if (!player) return;
    try {
      await archive.mutateAsync({ id: player.id });
      await queryClient.invalidateQueries({ queryKey: playersQueryKey() });
      toast({ title: 'Player archived', variant: 'success' });
      navigate('/players');
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    } finally {
      setArchiveOpen(false);
    }
  };

  return (
    <div className="flex flex-col gap-4">
      {returnTo ? (
        <Button asChild size="sm" className="self-start">
          <Link to={returnTo}>
            <ArrowLeft className="h-4 w-4" aria-hidden="true" /> Back to your booking
          </Link>
        </Button>
      ) : null}
      <Button asChild variant="ghost" size="sm" className="self-start">
        <Link to="/players">
          <ArrowLeft className="h-4 w-4" aria-hidden="true" /> Back to players
        </Link>
      </Button>

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {!player ? (
          <p className="text-sm text-muted-foreground">This player could not be found.</p>
        ) : (
          <>
            <PageHeader
              title={`${player.first_name} ${player.last_name}`}
              description={`Age ${player.age}`}
              actions={
                <Button variant="outline" onClick={() => setArchiveOpen(true)}>
                  <Archive className="h-4 w-4" aria-hidden="true" /> Archive
                </Button>
              }
            />

            <div className="flex flex-wrap gap-2">
              {player.has_medical_info ? (
                <Badge variant="warning">Medical info on file</Badge>
              ) : null}
              {player.no_pickup_restrictions ? (
                <Badge variant="outline">No pickup restrictions</Badge>
              ) : null}
            </div>

            <TabsView
              aria-label="Player sections"
              value={tab}
              onValueChange={(value) => setSearchParams({ tab: value }, { replace: true })}
              items={[
                {
                  value: 'profile',
                  label: 'Profile',
                  content: (
                    <div className="flex flex-col gap-6">
                      <section className="flex flex-col gap-3">
                        <h2 className="text-sm font-semibold">Basics</h2>
                        <PlayerBasicsForm player={player} />
                      </section>
                      <section className="flex flex-col gap-3">
                        <h2 className="text-sm font-semibold">Soccer profile</h2>
                        <PlayerProfileForm player={player} profile={player.profile ?? undefined} />
                      </section>
                    </div>
                  ),
                },
                {
                  value: 'contacts',
                  label: 'Contacts',
                  content: <EmergencyContactsSection playerId={player.id} />,
                },
                {
                  value: 'pickups',
                  label: 'Pickups',
                  content: <AuthorizedPickupsSection playerId={player.id} />,
                },
                {
                  value: 'medical',
                  label: 'Medical',
                  content: <MedicalSection playerId={player.id} />,
                },
                {
                  value: 'waivers',
                  label: 'Waivers',
                  content: (
                    <PlayerWaiversSection playerId={player.id} timezone={settings.timezone} />
                  ),
                },
                {
                  value: 'feedback',
                  label: 'Feedback',
                  content: <FeedbackSection playerId={player.id} timezone={settings.timezone} />,
                },
              ]}
            />
          </>
        )}
      </QueryState>

      <ConfirmDialog
        open={archiveOpen}
        onOpenChange={setArchiveOpen}
        title="Archive player?"
        description="The player will be hidden from booking. Existing bookings are kept."
        confirmLabel="Archive"
        destructive
        loading={archive.isPending}
        onConfirm={() => void confirmArchive()}
      />
    </div>
  );
}
