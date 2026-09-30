import { useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Button, Modal, RadioGroup, useToast } from '@scb/ui';
import {
  bookingsQueryKey,
  rebookOptionsQueryKey,
  useRebookBooking,
  useRebookOptions,
  type RebookOptions,
} from '../../api/endpoints';
import { body, errorMessage } from '../shared/api-utils';
import { usePortalSettings } from '../shared/extras';

function readString(
  record: Record<string, unknown> | null | undefined,
  key: string,
): string | undefined {
  const value = record?.[key];
  return typeof value === 'string' ? value : undefined;
}

export function RebookDialog({
  bookingId,
  open,
  onOpenChange,
}: {
  bookingId: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const query = useRebookOptions(bookingId, {
    query: { queryKey: rebookOptionsQueryKey(bookingId), enabled: open, retry: false },
  });
  const rebook = useRebookBooking();
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const settings = usePortalSettings();
  const [targetId, setTargetId] = useState<string | undefined>();
  const options = body<RebookOptions>(query);

  const confirm = async () => {
    if (!targetId) return;
    try {
      await rebook.mutateAsync({ id: bookingId, data: { target_session_id: targetId } });
      await queryClient.invalidateQueries({ queryKey: bookingsQueryKey() });
      toast({ title: 'Booking moved', variant: 'success' });
      onOpenChange(false);
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    }
  };

  return (
    <Modal
      open={open}
      onOpenChange={onOpenChange}
      title="Rebook"
      description="Choose another session for this player."
      footer={
        <>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button onClick={() => void confirm()} disabled={!targetId || rebook.isPending}>
            {rebook.isPending ? 'Moving…' : 'Move booking'}
          </Button>
        </>
      }
    >
      {query.isLoading ? (
        <p className="text-sm text-muted-foreground">Loading options…</p>
      ) : options && !options.allowed ? (
        <p className="text-sm text-muted-foreground">
          {options.reason ?? 'This booking cannot be rebooked.'}
        </p>
      ) : !options || options.sessions.length === 0 ? (
        <p className="text-sm text-muted-foreground">No alternative sessions are available.</p>
      ) : (
        <RadioGroup
          label="Eligible sessions"
          value={targetId}
          onValueChange={setTargetId}
          options={options.sessions.map((item) => {
            const session = item.session as Record<string, unknown>;
            const offering = item.offering as Record<string, unknown> | null;
            const startsAt = readString(session, 'starts_at');
            const id = readString(session, 'id') ?? '';
            return {
              value: id,
              label: `${readString(offering, 'name') ?? 'Session'} · ${
                startsAt ? formatLabel(startsAt, settings.timezone) : 'Time TBD'
              }`,
            };
          })}
        />
      )}
    </Modal>
  );
}

function formatLabel(instant: string, timezone: string): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone,
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(instant));
}
