import { useQueryClient } from '@tanstack/react-query';
import { Badge, Button, Card, CardContent, EmptyState } from '@scb/ui';
import { Inbox } from 'lucide-react';
import {
  useUpdateWebsiteContact,
  useWebsiteContacts,
  websiteContactsQueryKey,
  type WebsiteContactSubmission,
} from '../../api/endpoints';
import { listItems } from '../shared/api-utils';

export function WebsiteInbox() {
  const query = useWebsiteContacts();
  const update = useUpdateWebsiteContact();
  const client = useQueryClient();
  const contacts = listItems<WebsiteContactSubmission>(query);
  const setStatus = async (id: string, status: 'new' | 'read' | 'resolved') => {
    await update.mutateAsync({ id, data: { status } });
    await client.invalidateQueries({ queryKey: websiteContactsQueryKey() });
  };
  if (!query.isLoading && contacts.length === 0)
    return (
      <EmptyState
        icon={<Inbox className="h-8 w-8" />}
        title="No website inquiries"
        description="Messages from the public contact form will appear here."
      />
    );
  return (
    <div className="grid gap-4">
      {contacts.map((item) => (
        <Card key={item.id}>
          <CardContent className="space-y-4 pt-5">
            <div className="flex flex-wrap items-start justify-between gap-3">
              <div>
                <div className="flex items-center gap-2">
                  <h2 className="font-semibold">{item.name}</h2>
                  <Badge
                    variant={
                      item.status === 'new'
                        ? 'warning'
                        : item.status === 'resolved'
                          ? 'success'
                          : 'outline'
                    }
                  >
                    {item.status}
                  </Badge>
                </div>
                <a className="text-sm text-primary hover:underline" href={`mailto:${item.email}`}>
                  {item.email}
                </a>
                {item.phone ? <p className="text-sm text-muted-foreground">{item.phone}</p> : null}
              </div>
              <time className="text-xs text-muted-foreground">
                {item.inserted_at ? new Date(item.inserted_at).toLocaleString() : ''}
              </time>
            </div>
            <div>
              <p className="font-medium">{item.subject || 'Website inquiry'}</p>
              <p className="mt-2 whitespace-pre-wrap text-sm leading-6 text-muted-foreground">
                {item.message}
              </p>
            </div>
            <div className="flex gap-2">
              {item.status === 'new' ? (
                <Button size="sm" variant="outline" onClick={() => void setStatus(item.id, 'read')}>
                  Mark read
                </Button>
              ) : null}
              {item.status !== 'resolved' ? (
                <Button size="sm" onClick={() => void setStatus(item.id, 'resolved')}>
                  Resolve
                </Button>
              ) : (
                <Button size="sm" variant="outline" onClick={() => void setStatus(item.id, 'read')}>
                  Reopen
                </Button>
              )}
            </div>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}
