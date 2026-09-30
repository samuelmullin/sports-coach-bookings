import { Link, useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, Phone, ShieldAlert } from 'lucide-react';
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  EmptyState,
  formatDate,
} from '@scb/ui';
import { useCoachPlayer } from '../../api/endpoints';
import { errorMessage } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';
import { MarkdownPreview } from '../shared/MarkdownPreview';
import { MedicalReveal } from '../customers/MedicalReveal';
import { coachPlayerBody, isForbidden } from './coach-utils';
import type { CoachPlayer } from './types';

function fullName(player: CoachPlayer | undefined): string {
  if (!player) return 'Player';
  const preferred = player.preferred_name?.trim();
  const name = [player.first_name, player.last_name].filter(Boolean).join(' ').trim();
  return preferred || name || 'Player';
}

function Field({ label, value }: { label: string; value: React.ReactNode }) {
  if (value === null || value === undefined || value === '') return null;
  return (
    <div className="flex flex-col gap-0.5">
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className="text-sm">{value}</dd>
    </div>
  );
}

export function CoachPlayerDetailPage() {
  const { playerId = '' } = useParams();
  const navigate = useNavigate();
  const query = useCoachPlayer(playerId);
  const detail = coachPlayerBody(query);

  if (isForbidden(query.error)) {
    return (
      <EmptyState
        icon={<ShieldAlert className="h-8 w-8" />}
        title="Not on your roster"
        description="This player is not booked into any of your sessions."
        action={
          <Button asChild variant="outline">
            <Link to="/players">Back to players</Link>
          </Button>
        }
      />
    );
  }

  const player = detail?.player;
  const profile = player?.profile;
  const contacts = player?.emergency_contacts ?? [];
  const pickups = player?.authorized_pickups ?? [];
  const feedback = detail?.feedback ?? [];

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title={fullName(player)}
        description={typeof player?.age === 'number' ? `Age ${player.age}` : 'Player profile'}
        actions={
          <Button variant="outline" size="sm" onClick={() => navigate('/players')}>
            <ArrowLeft className="h-4 w-4" aria-hidden="true" />
            Back
          </Button>
        }
      />

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        <div className="grid gap-4 lg:grid-cols-2">
          <Card>
            <CardHeader>
              <CardTitle>Profile</CardTitle>
            </CardHeader>
            <CardContent>
              <dl className="grid gap-3 sm:grid-cols-2">
                <Field
                  label="Preferred positions"
                  value={profile?.preferred_positions?.join(', ')}
                />
                <Field label="Home club" value={profile?.home_club} />
                <Field label="Team" value={profile?.team} />
                <Field label="Dominant foot" value={profile?.dominant_foot} />
                <Field label="Goals" value={profile?.goals} />
                <Field label="Interests" value={profile?.interests} />
                <Field label="Notes from family" value={profile?.notes_from_family} />
              </dl>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Emergency contacts</CardTitle>
            </CardHeader>
            <CardContent>
              {contacts.length === 0 ? (
                <p className="text-sm text-muted-foreground">No emergency contacts on file.</p>
              ) : (
                <ul className="flex flex-col gap-3">
                  {contacts.map((contact) => (
                    <li key={contact.id} className="flex flex-col gap-0.5">
                      <span className="text-sm font-medium">
                        {contact.name}
                        {contact.relationship ? ` · ${contact.relationship}` : ''}
                      </span>
                      {contact.phone ? (
                        <a
                          className="inline-flex items-center gap-1 text-sm text-primary hover:underline"
                          href={`tel:${contact.phone}`}
                        >
                          <Phone className="h-4 w-4" aria-hidden="true" />
                          {contact.phone}
                        </a>
                      ) : null}
                    </li>
                  ))}
                </ul>
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Authorized pickups</CardTitle>
            </CardHeader>
            <CardContent>
              {pickups.length === 0 ? (
                <p className="text-sm text-muted-foreground">No authorized pickups on file.</p>
              ) : (
                <ul className="flex flex-col gap-3">
                  {pickups.map((pickup) => (
                    <li key={pickup.id} className="flex flex-col gap-0.5">
                      <span className="text-sm font-medium">
                        {pickup.name}
                        {pickup.relationship ? ` · ${pickup.relationship}` : ''}
                      </span>
                      {pickup.phone ? (
                        <a
                          className="inline-flex items-center gap-1 text-sm text-primary hover:underline"
                          href={`tel:${pickup.phone}`}
                        >
                          <Phone className="h-4 w-4" aria-hidden="true" />
                          {pickup.phone}
                        </a>
                      ) : null}
                    </li>
                  ))}
                </ul>
              )}
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Medical</CardTitle>
            </CardHeader>
            <CardContent>
              <MedicalReveal playerId={playerId} hasMedicalInfo={player?.has_medical_info} />
            </CardContent>
          </Card>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Previous feedback</CardTitle>
          </CardHeader>
          <CardContent>
            {feedback.length === 0 ? (
              <p className="text-sm text-muted-foreground">No feedback recorded yet.</p>
            ) : (
              <ul className="flex flex-col gap-3">
                {feedback.map((record) => (
                  <li key={record.id} className="rounded-md border border-border p-3">
                    <div className="mb-2 flex flex-wrap items-center gap-2">
                      <Badge variant={record.visibility === 'shared' ? 'success' : 'warning'}>
                        {record.visibility === 'shared' ? 'Shared' : 'Draft'}
                      </Badge>
                      {record.inserted_at ? (
                        <span className="text-xs text-muted-foreground">
                          {formatDate(record.inserted_at, 'UTC')}
                        </span>
                      ) : null}
                    </div>
                    <MarkdownPreview markdown={record.body} />
                    {record.focus_next ? (
                      <p className="mt-2 text-sm">
                        <span className="text-muted-foreground">Focus next: </span>
                        {record.focus_next}
                      </p>
                    ) : null}
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
      </QueryState>
    </div>
  );
}
