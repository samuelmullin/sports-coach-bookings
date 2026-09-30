import { useState } from 'react';
import { Badge, Button, FormField, Input, Modal, Select, Switch, useToast } from '@scb/ui';
import { applyApiFieldErrors } from '@scb/api-client';
import {
  useCreateBooking,
  useHouseholds,
  usePlayers,
  type BookingMethod,
} from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';

interface Household {
  id?: string;
  name?: string | null;
}
interface Player {
  id: string;
  first_name: string;
  last_name: string;
  household_id: string;
}

export function BookOnBehalfDialog({
  open,
  onOpenChange,
  sessionId,
  seatsLeft,
  onBooked,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  sessionId: string;
  seatsLeft?: number;
  onBooked?: () => void;
}) {
  const [householdQuery, setHouseholdQuery] = useState('');
  const [selectedHousehold, setSelectedHousehold] = useState<string>('');
  const [playerId, setPlayerId] = useState('');
  const [method, setMethod] = useState<BookingMethod>('credits');
  const [override, setOverride] = useState(false);
  const [reason, setReason] = useState('');
  const { toast } = useToast();

  const households = listItems<Household>(
    useHouseholds({ q: householdQuery || undefined, limit: 10 }),
  );
  const players = listItems<Player>(usePlayers({}));
  const householdPlayers = players.filter((player) => player.household_id === selectedHousehold);

  const createBooking = useCreateBooking();

  const reset = () => {
    setHouseholdQuery('');
    setSelectedHousehold('');
    setPlayerId('');
    setMethod('credits');
    setOverride(false);
    setReason('');
  };

  const submit = async () => {
    if (!playerId || !sessionId) return;
    try {
      await createBooking.mutateAsync({
        data: {
          session_id: sessionId,
          player_id: playerId,
          method,
          override,
          reason: reason || null,
        },
      });
      toast({ title: 'Booking created', variant: 'success' });
      reset();
      onOpenChange(false);
      onBooked?.();
    } catch (error) {
      const applied = applyApiFieldErrors(error, {
        setError: () => undefined,
        fallbackField: undefined,
      });
      if (!applied.handled) toast({ title: errorMessage(error), variant: 'danger' });
    }
  };

  return (
    <Modal
      open={open}
      onOpenChange={(next) => {
        if (!next) reset();
        onOpenChange(next);
      }}
      title="Book on behalf"
      description={`A seat is held immediately. ${seatsLeft != null ? `${seatsLeft} seats left.` : ''}`}
      footer={
        <>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button onClick={() => void submit()} disabled={!playerId || createBooking.isPending}>
            Book player
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <FormField label="Find household">
          <Input
            placeholder="Search households"
            value={householdQuery}
            onChange={(event) => setHouseholdQuery(event.target.value)}
          />
        </FormField>

        <div className="flex max-h-40 flex-col gap-1 overflow-auto">
          {households.length === 0 ? (
            <p className="text-sm text-muted-foreground">No households found.</p>
          ) : (
            households.map((household) => (
              <button
                key={household.id}
                type="button"
                onClick={() => {
                  setSelectedHousehold(household.id ?? '');
                  setPlayerId('');
                }}
                className={`flex items-center justify-between rounded-md border px-3 py-2 text-left text-sm ${
                  selectedHousehold === household.id ? 'border-primary bg-muted' : 'border-border'
                }`}
              >
                <span>{household.name ?? 'Unnamed household'}</span>
                {selectedHousehold === household.id ? (
                  <Badge variant="accent">Selected</Badge>
                ) : null}
              </button>
            ))
          )}
        </div>

        {selectedHousehold ? (
          <FormField label="Player">
            <Select
              aria-label="Player"
              placeholder="Choose a player"
              value={playerId}
              onValueChange={setPlayerId}
              options={householdPlayers.map((player) => ({
                value: player.id,
                label: `${player.first_name} ${player.last_name}`,
              }))}
            />
          </FormField>
        ) : null}

        <FormField label="Method">
          <Select
            aria-label="Method"
            value={method}
            onValueChange={(value) => setMethod(value as BookingMethod)}
            options={[
              { value: 'credits', label: 'Sessions' },
              { value: 'comp', label: 'Comp (no charge)' },
              { value: 'paid', label: 'Paid' },
            ]}
          />
        </FormField>

        <Switch
          label="Override restrictions (waivers, eligibility)"
          checked={override}
          onCheckedChange={setOverride}
        />
        {override ? (
          <FormField label="Override reason">
            <Input value={reason} onChange={(event) => setReason(event.target.value)} />
          </FormField>
        ) : null}
      </div>
    </Modal>
  );
}
