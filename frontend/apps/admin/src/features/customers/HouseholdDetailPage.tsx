import { useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  EmptyState,
  FormField,
  Input,
  Modal,
  MoneyDisplay,
  Table,
  TabsView,
  useToast,
} from '@scb/ui';
import {
  useAdjustCredits,
  useBookings,
  useDeliveries,
  useGrantCredits,
  useHousehold,
  useHouseholdCreditLedger,
  useHouseholdCredits,
  useOrders,
  usePlayers,
  useResendDelivery,
  type CreditLedgerEntry,
  type HouseholdDetail,
} from '../../api/endpoints';
import { body, errorMessage, listItems } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';
import { useTenantSettings } from '../shared/useTenantSettings';
import { MedicalReveal } from './MedicalReveal';

function MembersTab({ householdId }: { householdId: string }) {
  const query = useHousehold(householdId);
  const household = body<HouseholdDetail>(query);
  const members = household?.members ?? [];
  return (
    <Table
      caption="Household members"
      rowKey={(row) => row.id ?? row.customer_user_id ?? ''}
      columns={[
        {
          key: 'name',
          header: 'Name',
          cell: (row) =>
            [row.customer_user?.first_name, row.customer_user?.last_name]
              .filter(Boolean)
              .join(' ') ||
            row.customer_user?.email ||
            '—',
        },
        { key: 'email', header: 'Email', cell: (row) => row.customer_user?.email ?? '—' },
        { key: 'role', header: 'Role', cell: (row) => row.role ?? '—' },
        { key: 'relationship', header: 'Relationship', cell: (row) => row.relationship ?? '—' },
      ]}
      data={members}
    />
  );
}

function PlayersTab({ householdId }: { householdId: string }) {
  const players = listItems<{
    id: string;
    first_name: string;
    last_name: string;
    household_id: string;
    has_medical_info?: boolean | null;
    active: boolean;
  }>(usePlayers({}));
  const householdPlayers = players.filter((player) => player.household_id === householdId);

  return (
    <div className="flex flex-col gap-4">
      {householdPlayers.length === 0 ? (
        <EmptyState
          title="No players"
          description="Players added by this household will appear here."
        />
      ) : (
        householdPlayers.map((player) => (
          <Card key={player.id}>
            <CardHeader className="flex-row items-center justify-between">
              <CardTitle>
                {player.first_name} {player.last_name}
              </CardTitle>
              <Badge variant={player.active ? 'success' : 'outline'}>
                {player.active ? 'Active' : 'Inactive'}
              </Badge>
            </CardHeader>
            <CardContent>
              <MedicalReveal
                playerId={player.id}
                hasMedicalInfo={Boolean(player.has_medical_info)}
              />
            </CardContent>
          </Card>
        ))
      )}
    </div>
  );
}

function CreditsTab({ householdId }: { householdId: string }) {
  const { currency } = useTenantSettings();
  const creditsQuery = useHouseholdCredits(householdId);
  const ledgerQuery = useHouseholdCreditLedger(householdId, { limit: 25 });
  const grant = useGrantCredits();
  const adjust = useAdjustCredits();
  const { toast } = useToast();
  const [grantOpen, setGrantOpen] = useState(false);
  const [adjustOpen, setAdjustOpen] = useState(false);
  const [amount, setAmount] = useState(1);
  const [delta, setDelta] = useState(1);
  const [note, setNote] = useState('');
  const [validityDays, setValidityDays] = useState<number | null>(365);

  const balances = body<{
    data: { amount: number; offering_id: string | null; nearest_expiry?: string | null }[];
  }>(creditsQuery)?.data;

  const ledger = listItems<CreditLedgerEntry>(ledgerQuery);

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader className="flex-row items-center justify-between">
          <CardTitle>Balance</CardTitle>
          <div className="flex gap-2">
            <Button variant="outline" size="sm" onClick={() => setGrantOpen(true)}>
              Grant sessions
            </Button>
            <Button variant="outline" size="sm" onClick={() => setAdjustOpen(true)}>
              Adjust
            </Button>
          </div>
        </CardHeader>
        <CardContent>
          {!balances || balances.length === 0 ? (
            <p className="text-sm text-muted-foreground">No sessions on file.</p>
          ) : (
            <ul className="flex flex-col gap-2">
              {balances.map((balance) => (
                <li
                  key={balance.offering_id ?? 'any'}
                  className="flex items-center justify-between text-sm"
                >
                  <span>
                    {balance.offering_id === 'any' || !balance.offering_id
                      ? 'Any offering'
                      : balance.offering_id}
                  </span>
                  <span className="flex items-center gap-3">
                    <Badge variant="accent">{balance.amount} sessions</Badge>
                    {balance.nearest_expiry ? (
                      <span className="text-xs text-muted-foreground">
                        expires {new Date(balance.nearest_expiry).toLocaleDateString()}
                      </span>
                    ) : null}
                  </span>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Ledger</CardTitle>
        </CardHeader>
        <CardContent>
          {ledger.length === 0 ? (
            <p className="text-sm text-muted-foreground">No ledger entries.</p>
          ) : (
            <Table
              caption="Session ledger"
              rowKey={(row) => row.id}
              columns={[
                {
                  key: 'when',
                  header: 'When',
                  cell: (row) =>
                    row.inserted_at ? new Date(row.inserted_at).toLocaleString() : '—',
                },
                { key: 'reason', header: 'Reason', cell: (row) => row.reason },
                {
                  key: 'delta',
                  header: 'Change',
                  align: 'right',
                  cell: (row) => (
                    <span className={row.delta >= 0 ? 'text-green-700' : 'text-danger'}>
                      {row.delta > 0 ? '+' : ''}
                      {row.delta}
                    </span>
                  ),
                },
                { key: 'note', header: 'Note', cell: (row) => row.note ?? '—' },
              ]}
              data={ledger}
            />
          )}
        </CardContent>
      </Card>

      <Modal
        open={grantOpen}
        onOpenChange={setGrantOpen}
        title="Grant sessions"
        footer={
          <>
            <Button variant="outline" onClick={() => setGrantOpen(false)}>
              Cancel
            </Button>
            <Button
              onClick={() =>
                void grant
                  .mutateAsync({
                    householdId,
                    data: { amount, note: note || null, validity_days: validityDays },
                  })
                  .then(() => {
                    toast({ title: 'Sessions granted', variant: 'success' });
                    setGrantOpen(false);
                    void creditsQuery.refetch();
                    void ledgerQuery.refetch();
                  })
                  .catch((error) => toast({ title: errorMessage(error), variant: 'danger' }))
              }
              disabled={grant.isPending}
            >
              Grant
            </Button>
          </>
        }
      >
        <div className="flex flex-col gap-4">
          <FormField label="Sessions">
            <Input
              type="number"
              value={amount}
              onChange={(e) => setAmount(Number(e.target.value))}
            />
          </FormField>
          <FormField label="Validity (days)">
            <Input
              type="number"
              value={validityDays ?? ''}
              onChange={(e) =>
                setValidityDays(e.target.value === '' ? null : Number(e.target.value))
              }
            />
          </FormField>
          <FormField label="Note">
            <Input value={note} onChange={(e) => setNote(e.target.value)} />
          </FormField>
          <p className="text-xs text-muted-foreground">Currency: {currency}</p>
        </div>
      </Modal>

      <Modal
        open={adjustOpen}
        onOpenChange={setAdjustOpen}
        title="Adjust sessions"
        footer={
          <>
            <Button variant="outline" onClick={() => setAdjustOpen(false)}>
              Cancel
            </Button>
            <Button
              onClick={() =>
                void adjust
                  .mutateAsync({ householdId, data: { delta, note: note || null } })
                  .then(() => {
                    toast({ title: 'Sessions adjusted', variant: 'success' });
                    setAdjustOpen(false);
                    void creditsQuery.refetch();
                    void ledgerQuery.refetch();
                  })
                  .catch((error) => toast({ title: errorMessage(error), variant: 'danger' }))
              }
              disabled={adjust.isPending}
            >
              Adjust
            </Button>
          </>
        }
      >
        <div className="flex flex-col gap-4">
          <FormField label="Signed change">
            <Input type="number" value={delta} onChange={(e) => setDelta(Number(e.target.value))} />
          </FormField>
          <FormField label="Note">
            <Input value={note} onChange={(e) => setNote(e.target.value)} />
          </FormField>
        </div>
      </Modal>
    </div>
  );
}

function BookingsTab({ householdId }: { householdId: string }) {
  const bookings = listItems<{
    booking: { id: string; status: string; player_id: string; session_id: string };
  }>(useBookings({ household_id: householdId, limit: 25 }));

  if (bookings.length === 0)
    return <EmptyState title="No bookings" description="This household has no bookings." />;
  return (
    <Table
      caption="Household bookings"
      rowKey={(row) => row.booking.id}
      columns={[
        { key: 'player', header: 'Player', cell: (row) => row.booking.player_id },
        { key: 'session', header: 'Session', cell: (row) => row.booking.session_id },
        {
          key: 'status',
          header: 'Status',
          cell: (row) => <Badge variant="secondary">{row.booking.status}</Badge>,
        },
      ]}
      data={bookings}
    />
  );
}

function OrdersTab({ householdId }: { householdId: string }) {
  const orders = listItems<{
    id: string;
    number: string;
    total: number;
    currency: string;
    status: string;
  }>(useOrders({ household_id: householdId, limit: 25 }));
  if (orders.length === 0)
    return <EmptyState title="No orders" description="This household has no orders." />;
  return (
    <Table
      caption="Household orders"
      rowKey={(row) => row.id}
      columns={[
        {
          key: 'number',
          header: 'Order',
          cell: (row) => (
            <Link className="font-medium text-primary hover:underline" to={`/orders/${row.id}`}>
              {row.number}
            </Link>
          ),
        },
        {
          key: 'status',
          header: 'Status',
          cell: (row) => <Badge variant="secondary">{row.status}</Badge>,
        },
        {
          key: 'total',
          header: 'Total',
          align: 'right',
          cell: (row) => <MoneyDisplay amountMinor={row.total} currency={row.currency} />,
        },
      ]}
      data={orders}
    />
  );
}

function EmailsTab({ householdId }: { householdId: string }) {
  const deliveries = listItems<{
    id: string;
    subject?: string | null;
    email: string;
    status: string;
    sent_at?: string | null;
  }>(useDeliveries({ household_id: householdId, limit: 25 }));
  const resend = useResendDelivery();
  const { toast } = useToast();

  if (deliveries.length === 0)
    return <EmptyState title="No emails" description="Email delivery history will appear here." />;
  return (
    <Table
      caption="Email deliveries"
      rowKey={(row) => row.id}
      columns={[
        { key: 'subject', header: 'Subject', cell: (row) => row.subject ?? '—' },
        { key: 'email', header: 'To', cell: (row) => row.email },
        {
          key: 'status',
          header: 'Status',
          cell: (row) => <Badge variant="secondary">{row.status}</Badge>,
        },
        {
          key: 'sent',
          header: 'Sent',
          cell: (row) => (row.sent_at ? new Date(row.sent_at).toLocaleString() : '—'),
        },
        {
          key: 'actions',
          header: '',
          align: 'right',
          cell: (row) => (
            <Button
              variant="ghost"
              size="sm"
              onClick={() =>
                void resend
                  .mutateAsync({ id: row.id })
                  .then(() => toast({ title: 'Email re-sent', variant: 'success' }))
                  .catch((error) => toast({ title: errorMessage(error), variant: 'danger' }))
              }
            >
              Resend
            </Button>
          ),
        },
      ]}
      data={deliveries}
    />
  );
}

export function HouseholdDetailPage() {
  const { householdId = '' } = useParams();
  const query = useHousehold(householdId);
  const household = body<HouseholdDetail>(query);

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title={household?.name ?? 'Household'}
        description="Members, players, sessions, bookings, orders and email history."
      />
      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        <TabsView
          aria-label="Household sections"
          items={[
            {
              value: 'members',
              label: 'Members',
              content: <MembersTab householdId={householdId} />,
            },
            {
              value: 'players',
              label: 'Players',
              content: <PlayersTab householdId={householdId} />,
            },
            {
              value: 'credits',
              label: 'Sessions',
              content: <CreditsTab householdId={householdId} />,
            },
            {
              value: 'bookings',
              label: 'Bookings',
              content: <BookingsTab householdId={householdId} />,
            },
            { value: 'orders', label: 'Orders', content: <OrdersTab householdId={householdId} /> },
            { value: 'emails', label: 'Emails', content: <EmailsTab householdId={householdId} /> },
          ]}
        />
      </QueryState>
    </div>
  );
}
