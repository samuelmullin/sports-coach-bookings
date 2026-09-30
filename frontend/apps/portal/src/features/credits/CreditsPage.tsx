import { Link } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { Coins, ExternalLink } from 'lucide-react';
import { Badge, Card, CardContent, EmptyState, TabsView } from '@scb/ui';
import {
  useCreditLedger,
  useCreditLots,
  useCredits,
  useOfferings,
  type CreditBalance,
  type CreditLedgerEntry,
  type CreditLot,
  type OfferingResponse,
} from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { QueryState } from '../shared/QueryState';
import { PageHeader } from '../shared/PageHeader';
import { VenueTime } from '../shared/VenueTime';
import { usePortalSettings } from '../shared/extras';

function useOfferingNames() {
  const offerings = listItems<OfferingResponse>(useOfferings());
  const map = new Map(offerings.map((offering) => [offering.id, offering.name]));
  return (offeringId: string | null | undefined) => {
    if (!offeringId || offeringId === 'any') return 'Any offering';
    return map.get(offeringId) ?? 'Offering';
  };
}

function BalanceTab() {
  const query = useCredits();
  const settings = usePortalSettings();
  const offeringName = useOfferingNames();
  const credits = listItems<CreditBalance>(query);

  return (
    <QueryState
      loading={query.isLoading}
      error={query.isError ? errorMessage(query.error) : undefined}
      onRetry={() => void query.refetch()}
    >
      {credits.length === 0 ? (
        <EmptyState
          icon={<Coins className="h-8 w-8" />}
          title="No sessions"
          description="Buy a package to get sessions."
          action={
            <Link className="text-sm font-medium text-primary hover:underline" to="/packages">
              Browse packages
            </Link>
          }
        />
      ) : (
        <ul className="grid gap-3 sm:grid-cols-2">
          {credits.map((balance) => (
            <li key={balance.offering_id ?? 'any'}>
              <Card>
                <CardContent className="flex flex-col gap-1 pt-4">
                  <span className="text-sm text-muted-foreground">
                    {offeringName(balance.offering_id)}
                  </span>
                  <span className="text-2xl font-semibold">{balance.amount}</span>
                  {balance.nearest_expiry ? (
                    <span className="text-xs text-muted-foreground">
                      Earliest expiry{' '}
                      <VenueTime
                        instant={balance.nearest_expiry}
                        timezone={settings.timezone}
                        pattern="MMM d, yyyy"
                      />
                    </span>
                  ) : (
                    <span className="text-xs text-muted-foreground">No expiry</span>
                  )}
                  {balance.offering_id && balance.offering_id !== 'any' ? (
                    <Link
                      className="pt-1 text-sm font-medium text-primary hover:underline"
                      to={`/offerings/${balance.offering_id}/schedule`}
                    >
                      Book sessions
                    </Link>
                  ) : null}
                </CardContent>
              </Card>
            </li>
          ))}
        </ul>
      )}
    </QueryState>
  );
}

function LedgerTab() {
  const query = useCreditLedger({ limit: 25 });
  const settings = usePortalSettings();
  const entries = listItems<CreditLedgerEntry>(query);

  return (
    <QueryState
      loading={query.isLoading}
      error={query.isError ? errorMessage(query.error) : undefined}
      onRetry={() => void query.refetch()}
    >
      {entries.length === 0 ? (
        <EmptyState icon={<Coins className="h-8 w-8" />} title="No session activity yet" />
      ) : (
        <ul className="flex flex-col divide-y divide-border rounded-lg border border-border">
          {entries.map((entry) => (
            <li key={entry.id} className="flex items-center justify-between gap-3 p-3 text-sm">
              <div className="flex flex-col">
                <span className="font-medium capitalize">{entry.reason}</span>
                {entry.note ? (
                  <span className="text-xs text-muted-foreground">{entry.note}</span>
                ) : null}
                {entry.inserted_at ? (
                  <VenueTime
                    instant={entry.inserted_at}
                    timezone={settings.timezone}
                    pattern="MMM d, yyyy"
                    className="text-xs text-muted-foreground"
                  />
                ) : null}
              </div>
              <span
                className={
                  entry.delta >= 0 ? 'font-medium text-green-700' : 'font-medium text-danger'
                }
              >
                {entry.delta >= 0 ? '+' : ''}
                {entry.delta}
              </span>
            </li>
          ))}
        </ul>
      )}
    </QueryState>
  );
}

function LotsTab() {
  const query = useCreditLots({ limit: 25 });
  const settings = usePortalSettings();
  const lots = listItems<CreditLot>(query);

  return (
    <QueryState
      loading={query.isLoading}
      error={query.isError ? errorMessage(query.error) : undefined}
      onRetry={() => void query.refetch()}
    >
      {lots.length === 0 ? (
        <EmptyState icon={<Coins className="h-8 w-8" />} title="No session lots" />
      ) : (
        <ul className="flex flex-col gap-2">
          {lots.map((lot) => (
            <li key={lot.id}>
              <Card>
                <CardContent className="flex flex-wrap items-center justify-between gap-2 pt-4 text-sm">
                  <div className="flex flex-col gap-0.5">
                    <span className="font-medium capitalize">{lot.source.replace(/_/g, ' ')}</span>
                    <span className="text-xs text-muted-foreground">
                      Granted{' '}
                      <VenueTime
                        instant={lot.granted_at}
                        timezone={settings.timezone}
                        pattern="MMM d, yyyy"
                      />
                      {lot.expires_at ? (
                        <>
                          {' · '}Expires{' '}
                          <VenueTime
                            instant={lot.expires_at}
                            timezone={settings.timezone}
                            pattern="MMM d, yyyy"
                          />
                        </>
                      ) : null}
                    </span>
                  </div>
                  <Badge variant={lot.remaining > 0 ? 'success' : 'outline'}>
                    {lot.remaining} / {lot.quantity_granted} remaining
                  </Badge>
                </CardContent>
              </Card>
            </li>
          ))}
        </ul>
      )}
    </QueryState>
  );
}

export function CreditsPage() {
  const { t } = useTranslation();
  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title={t('credits.title')}
        description={t('credits.subtitle')}
        actions={
          <Link
            to="/packages"
            className="inline-flex items-center gap-1 text-sm font-medium text-primary hover:underline"
          >
            Buy sessions <ExternalLink className="h-3.5 w-3.5" aria-hidden="true" />
          </Link>
        }
      />
      <TabsView
        aria-label="Session sections"
        items={[
          { value: 'balance', label: 'Balance', content: <BalanceTab /> },
          { value: 'history', label: 'History', content: <LedgerTab /> },
          { value: 'lots', label: 'Expiry', content: <LotsTab /> },
        ]}
      />
    </div>
  );
}
