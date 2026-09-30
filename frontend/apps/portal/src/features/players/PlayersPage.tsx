import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { CheckCircle2, Plus, UserRound, XCircle } from 'lucide-react';
import { Badge, Button, Card, CardContent, EmptyState } from '@scb/ui';
import {
  useHouseholdWaiverStatus,
  usePlayers,
  type HouseholdWaiverStatusResponse,
  type PlayerResponse,
} from '../../api/endpoints';
import { body, errorMessage, listItems } from '../shared/api-utils';
import { QueryState } from '../shared/QueryState';
import { PageHeader } from '../shared/PageHeader';
import { PlayerWizard } from './PlayerWizard';

function ReadyChecklist({
  player,
  waiversSigned,
}: {
  player: PlayerResponse;
  waiversSigned: boolean;
}) {
  const hasContacts = (player.emergency_contacts?.length ?? 0) > 0;
  const items = [
    { label: 'Emergency contact', ok: hasContacts },
    { label: 'Waivers signed', ok: waiversSigned },
  ];
  return (
    <ul className="flex flex-wrap gap-3 text-xs">
      {items.map((item) => (
        <li key={item.label} className="flex items-center gap-1">
          {item.ok ? (
            <CheckCircle2 className="h-3.5 w-3.5 text-green-600" aria-hidden="true" />
          ) : (
            <XCircle className="h-3.5 w-3.5 text-amber-600" aria-hidden="true" />
          )}
          <span className={item.ok ? 'text-muted-foreground' : 'text-foreground'}>
            {item.label}
          </span>
        </li>
      ))}
    </ul>
  );
}

export function PlayersPage() {
  const { t } = useTranslation();
  const query = usePlayers();
  const waiversQuery = useHouseholdWaiverStatus();
  const [wizardOpen, setWizardOpen] = useState(false);

  const players = listItems<PlayerResponse>(query);
  const waiverStatus = body<HouseholdWaiverStatusResponse>(waiversQuery);
  const waiverByPlayer = new Map(
    (waiverStatus?.players ?? []).map((entry) => [entry.player_id, entry]),
  );

  const waiversSigned = (player: PlayerResponse) => {
    const entry = waiverByPlayer.get(player.id);
    const required = entry?.waivers.filter((waiver) => waiver.required) ?? [];
    return required.length === 0 || required.every((waiver) => waiver.signed);
  };

  const isReady = (player: PlayerResponse) => {
    const hasContacts = (player.emergency_contacts?.length ?? 0) > 0;
    return waiversSigned(player) && hasContacts;
  };

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title={t('nav.players')}
        description="Players you can book into sessions."
        actions={
          <Button onClick={() => setWizardOpen(true)}>
            <Plus className="h-4 w-4" aria-hidden="true" /> Add player
          </Button>
        }
      />

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {players.length === 0 ? (
          <EmptyState
            icon={<UserRound className="h-8 w-8" />}
            title={t('empty.players')}
            description="Add a player to start booking."
            action={
              <Button onClick={() => setWizardOpen(true)}>
                <Plus className="h-4 w-4" aria-hidden="true" /> Add player
              </Button>
            }
          />
        ) : (
          <ul className="grid gap-3 sm:grid-cols-2">
            {players.map((player) => (
              <li key={player.id}>
                <Card>
                  <CardContent className="flex flex-col gap-3 pt-4">
                    <div className="flex items-start justify-between gap-2">
                      <div className="flex flex-col gap-0.5">
                        <h2 className="font-medium">
                          {player.first_name} {player.last_name}
                        </h2>
                        <span className="text-sm text-muted-foreground">
                          {player.preferred_name ? `“${player.preferred_name}” · ` : ''}
                          Age {player.age}
                        </span>
                      </div>
                      {isReady(player) ? (
                        <Badge variant="success">Ready to book</Badge>
                      ) : (
                        <Badge variant="warning">Action needed</Badge>
                      )}
                    </div>
                    <ReadyChecklist player={player} waiversSigned={waiversSigned(player)} />
                    <Link
                      to={`/players/${player.id}`}
                      className="text-sm font-medium text-primary hover:underline"
                    >
                      Manage player
                    </Link>
                  </CardContent>
                </Card>
              </li>
            ))}
          </ul>
        )}
      </QueryState>

      <PlayerWizard open={wizardOpen} onOpenChange={setWizardOpen} />
    </div>
  );
}
