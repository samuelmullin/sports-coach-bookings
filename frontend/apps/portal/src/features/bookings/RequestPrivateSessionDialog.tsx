import { useState } from 'react';
import { Button, FormField, Input, Modal, useToast } from '@scb/ui';
import { useRequestPrivateSession } from '../../api/endpoints';
import { errorMessage } from '../shared/api-utils';

export function RequestPrivateSessionDialog({
  offeringId,
  maxPlayers,
  open,
  onOpenChange,
}: {
  offeringId: string;
  maxPlayers: number;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const request = useRequestPrivateSession();
  const { toast } = useToast();
  const [playerCount, setPlayerCount] = useState(1);
  const [preferredTime, setPreferredTime] = useState('');
  const [notes, setNotes] = useState('');

  const submit = async () => {
    try {
      await request.mutateAsync({
        data: {
          offering_id: offeringId,
          player_count: playerCount,
          preferred_times: preferredTime ? [new Date(preferredTime).toISOString()] : [],
          notes: notes || null,
        },
      });
      toast({ title: 'Private session request sent', variant: 'success' });
      onOpenChange(false);
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    }
  };

  return (
    <Modal
      open={open}
      onOpenChange={onOpenChange}
      title="Request a private session"
      description="The operator will confirm the time and coach before you pay."
      footer={
        <>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button
            onClick={() => void submit()}
            disabled={request.isPending || playerCount < 1 || playerCount > maxPlayers}
          >
            {request.isPending ? 'Sending…' : 'Send request'}
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <FormField label={`Number of players (up to ${maxPlayers})`}>
          <Input
            type="number"
            min={1}
            max={maxPlayers}
            value={playerCount}
            onChange={(event) => setPlayerCount(Number(event.target.value))}
          />
        </FormField>
        <FormField label="Preferred date and time">
          <Input
            type="datetime-local"
            value={preferredTime}
            onChange={(event) => setPreferredTime(event.target.value)}
          />
        </FormField>
        <FormField label="Notes">
          <Input
            value={notes}
            onChange={(event) => setNotes(event.target.value)}
            placeholder="Other times that work, goals, or questions"
          />
        </FormField>
      </div>
    </Modal>
  );
}
