import { useEffect, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { Badge, Switch, useToast } from '@scb/ui';
import {
  notificationPreferencesQueryKey,
  useNotificationPreferences,
  useUpdateNotificationPreferences,
  type NotificationPreferences,
} from '../../api/endpoints';
import { body, errorMessage } from '../shared/api-utils';
import { QueryState } from '../shared/QueryState';

export function NotificationPreferencesForm() {
  const query = useNotificationPreferences();
  const mutation = useUpdateNotificationPreferences();
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const preferences = body<NotificationPreferences>(query);
  const [marketing, setMarketing] = useState(false);

  useEffect(() => {
    if (preferences) setMarketing(preferences.marketing_opt_in);
  }, [preferences]);

  const onChange = async (checked: boolean) => {
    setMarketing(checked);
    try {
      await mutation.mutateAsync({ data: { marketing_opt_in: checked } });
      await queryClient.invalidateQueries({ queryKey: notificationPreferencesQueryKey() });
      toast({ title: 'Notification preferences saved', variant: 'success' });
    } catch (error) {
      setMarketing(!checked);
      toast({ title: errorMessage(error), variant: 'danger' });
    }
  };

  return (
    <QueryState
      loading={query.isLoading}
      error={query.isError ? errorMessage(query.error) : undefined}
      onRetry={() => void query.refetch()}
    >
      <div className="flex max-w-xl flex-col gap-5">
        <div className="flex items-start justify-between gap-4 rounded-lg border border-border p-4">
          <div className="flex flex-col gap-1">
            <span className="text-sm font-medium">Booking &amp; account emails</span>
            <span className="text-sm text-muted-foreground">
              Confirmations, reminders and receipts. These are always sent.
            </span>
          </div>
          <Badge variant="outline">Always on</Badge>
        </div>

        <div className="flex items-start justify-between gap-4 rounded-lg border border-border p-4">
          <div className="flex flex-col gap-1">
            <span className="text-sm font-medium">Club announcements</span>
            <span className="text-sm text-muted-foreground">
              Schedule changes and operational notices from the club.
            </span>
          </div>
          <Badge variant="outline">Always on</Badge>
        </div>

        <div className="flex items-start justify-between gap-4 rounded-lg border border-border p-4">
          <div className="flex flex-col gap-1">
            <span className="text-sm font-medium">Marketing emails</span>
            <span className="text-sm text-muted-foreground">
              I agree to receive promotional emails from this club, including offers, camps and
              merchandise. You can withdraw your consent at any time by turning this off.
            </span>
          </div>
          <Switch
            label="Marketing emails"
            checked={marketing}
            disabled={mutation.isPending}
            onCheckedChange={(checked) => void onChange(checked)}
          />
        </div>
      </div>
    </QueryState>
  );
}
