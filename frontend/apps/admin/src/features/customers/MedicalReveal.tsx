import { useState } from 'react';
import { ShieldAlert } from 'lucide-react';
import { Button } from '@scb/ui';
import {
  usePlayerMedical,
  playerMedicalQueryKey,
  type MedicalInfoResponse,
} from '../../api/endpoints';
import { body, errorMessage } from '../shared/api-utils';

export function MedicalReveal({
  playerId,
  hasMedicalInfo,
}: {
  playerId: string;
  hasMedicalInfo?: boolean;
}) {
  const [revealed, setRevealed] = useState(false);
  const query = usePlayerMedical(playerId, {
    query: { enabled: revealed, queryKey: playerMedicalQueryKey(playerId) },
  });
  const medical = body<MedicalInfoResponse>(query);

  if (!revealed) {
    return (
      <div className="flex flex-col gap-2">
        <Button variant="outline" size="sm" onClick={() => setRevealed(true)}>
          <ShieldAlert className="h-4 w-4" aria-hidden="true" />
          {hasMedicalInfo ? 'Reveal medical info' : 'Check medical info'}
        </Button>
        <p className="text-xs text-muted-foreground">
          Revealing medical information is recorded in the audit log.
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="rounded-md border border-amber-300 bg-amber-50 p-2 text-xs text-amber-900">
        This medical information is sensitive. Your access has been recorded in the audit log.
      </div>
      {query.isLoading ? (
        <p className="text-sm text-muted-foreground">Loading…</p>
      ) : query.isError ? (
        <p className="text-sm text-danger">{errorMessage(query.error)}</p>
      ) : !medical?.has_medical_info ? (
        <p className="text-sm text-muted-foreground">No medical information on file.</p>
      ) : (
        <dl className="grid gap-2 text-sm">
          <div>
            <dt className="text-xs text-muted-foreground">Allergies</dt>
            <dd>{medical.allergies || '—'}</dd>
          </div>
          <div>
            <dt className="text-xs text-muted-foreground">Conditions</dt>
            <dd>{medical.conditions || '—'}</dd>
          </div>
          <div>
            <dt className="text-xs text-muted-foreground">Medications</dt>
            <dd>{medical.medications || '—'}</dd>
          </div>
          <div>
            <dt className="text-xs text-muted-foreground">Notes</dt>
            <dd>{medical.notes || '—'}</dd>
          </div>
        </dl>
      )}
    </div>
  );
}
