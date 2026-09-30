import { useState } from 'react';
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Checkbox,
  EmptyState,
  FormField,
  Input,
  Select,
  Table,
  Textarea,
  useToast,
} from '@scb/ui';
import { useOfferings, useVenues } from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { MarkdownPreview } from '../shared/MarkdownPreview';
import { PageHeader } from '../shared/PageHeader';
import {
  useBroadcasts,
  useCreateBroadcast,
  useRecipientCount,
  useSendTestBroadcast,
  type BroadcastCategory,
  type BroadcastSegment,
} from '../../api/extras';

const EMPTY_SEGMENT: BroadcastSegment = { venue_ids: [], offering_ids: [], household_ids: [] };

const CATEGORY_HELP: Record<BroadcastCategory, string> = {
  operational:
    'Operational messages are transactional (schedule changes, pickup reminders). Customers cannot unsubscribe from these.',
  marketing:
    'Marketing messages are promotional. Customers who opted out of marketing will be excluded automatically.',
};

export function MessagingPage() {
  const venues = listItems<{ id: string; name: string }>(useVenues());
  const offerings = listItems<{ id: string; name: string }>(useOfferings());
  const createBroadcast = useCreateBroadcast();
  const sendTest = useSendTestBroadcast();
  const { toast } = useToast();

  const [subject, setSubject] = useState('');
  const [body, setBody] = useState('');
  const [category, setCategory] = useState<BroadcastCategory>('operational');
  const [segment, setSegment] = useState<BroadcastSegment>(EMPTY_SEGMENT);
  const [scheduledAt, setScheduledAt] = useState('');

  const recipientQuery = useRecipientCount(segment);
  const historyQuery = useBroadcasts();
  const recipientCount = recipientQuery.data?.count ?? 0;

  const toggle = (key: 'venue_ids' | 'offering_ids', id: string) =>
    setSegment((current) => ({
      ...current,
      [key]: current[key].includes(id)
        ? current[key].filter((value) => value !== id)
        : [...current[key], id],
    }));

  const input = {
    subject,
    body_markdown: body,
    category,
    segment,
    scheduled_at: scheduledAt ? new Date(scheduledAt).toISOString() : null,
  };

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title="Broadcasts"
        description="Email everyone, or a segment, with operational or marketing messages."
      />

      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Composer</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-4">
            <FormField label="Subject" required>
              <Input value={subject} onChange={(event) => setSubject(event.target.value)} />
            </FormField>
            <FormField label="Message (markdown)">
              <Textarea
                aria-label="Message"
                className="min-h-[200px] font-mono text-xs"
                value={body}
                onChange={(event) => setBody(event.target.value)}
              />
            </FormField>
            <FormField label="Category" help={CATEGORY_HELP[category]}>
              <Select
                aria-label="Category"
                value={category}
                onValueChange={(value) => setCategory(value as BroadcastCategory)}
                options={[
                  { value: 'operational', label: 'Operational' },
                  { value: 'marketing', label: 'Marketing' },
                ]}
              />
            </FormField>
            <FormField label="Schedule for later" help="Leave blank to send immediately.">
              <Input
                type="datetime-local"
                value={scheduledAt}
                onChange={(event) => setScheduledAt(event.target.value)}
              />
            </FormField>
            <div className="flex flex-wrap justify-end gap-2">
              <Button
                variant="outline"
                disabled={sendTest.isPending || !subject}
                onClick={() =>
                  void sendTest
                    .mutateAsync(input)
                    .then(() => toast({ title: 'Test email sent to you', variant: 'success' }))
                    .catch((error) => toast({ title: errorMessage(error), variant: 'danger' }))
                }
              >
                Send test to me
              </Button>
              <Button
                disabled={createBroadcast.isPending || !subject}
                onClick={() =>
                  void createBroadcast
                    .mutateAsync(input)
                    .then(() => {
                      toast({
                        title: scheduledAt ? 'Broadcast scheduled' : 'Broadcast sending',
                        variant: 'success',
                      });
                      setSubject('');
                      setBody('');
                      setScheduledAt('');
                    })
                    .catch((error) => toast({ title: errorMessage(error), variant: 'danger' }))
                }
              >
                {scheduledAt ? 'Schedule broadcast' : 'Send now'}
              </Button>
            </div>
          </CardContent>
        </Card>

        <div className="flex flex-col gap-4">
          <Card>
            <CardHeader>
              <CardTitle>Segment</CardTitle>
            </CardHeader>
            <CardContent className="flex flex-col gap-4">
              <div>
                <p className="mb-2 text-sm font-medium">Venues</p>
                <div className="flex flex-col gap-2">
                  {venues.map((venue) => (
                    <Checkbox
                      key={venue.id}
                      label={venue.name}
                      checked={segment.venue_ids.includes(venue.id)}
                      onCheckedChange={() => toggle('venue_ids', venue.id)}
                    />
                  ))}
                </div>
              </div>
              <div>
                <p className="mb-2 text-sm font-medium">Offerings</p>
                <div className="flex flex-col gap-2">
                  {offerings.map((offering) => (
                    <Checkbox
                      key={offering.id}
                      label={offering.name}
                      checked={segment.offering_ids.includes(offering.id)}
                      onCheckedChange={() => toggle('offering_ids', offering.id)}
                    />
                  ))}
                </div>
              </div>
              <div className="flex items-center justify-between rounded-md bg-muted p-3">
                <span className="text-sm font-medium">Recipients</span>
                <Badge variant="accent" data-testid="recipient-count">
                  {recipientQuery.isLoading ? '…' : `${recipientCount} households`}
                </Badge>
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Preview</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="rounded-md border border-border p-3">
                <p className="text-sm font-semibold">{subject || 'Subject line'}</p>
                <div className="mt-2">
                  <MarkdownPreview markdown={body || '_Write your message to see a preview._'} />
                </div>
              </div>
            </CardContent>
          </Card>
        </div>
      </div>

      <Card>
        <CardHeader>
          <CardTitle>History</CardTitle>
        </CardHeader>
        <CardContent>
          {(historyQuery.data ?? []).length === 0 ? (
            <EmptyState
              title="No broadcasts yet"
              description="Sent and scheduled broadcasts appear here."
            />
          ) : (
            <Table
              caption="Broadcast history"
              rowKey={(row) => row.id}
              columns={[
                { key: 'subject', header: 'Subject', cell: (row) => row.subject },
                {
                  key: 'category',
                  header: 'Category',
                  cell: (row) => <Badge variant="secondary">{row.category}</Badge>,
                },
                {
                  key: 'status',
                  header: 'Status',
                  cell: (row) => (
                    <Badge variant={row.status === 'sent' ? 'success' : 'warning'}>
                      {row.status}
                    </Badge>
                  ),
                },
                { key: 'recipients', header: 'Recipients', cell: (row) => row.recipient_count },
                {
                  key: 'delivered',
                  header: 'Delivered / opened',
                  cell: (row) => `${row.delivered_count} / ${row.open_count}`,
                },
              ]}
              data={historyQuery.data ?? []}
            />
          )}
        </CardContent>
      </Card>
    </div>
  );
}
