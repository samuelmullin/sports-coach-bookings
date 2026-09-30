import { Link } from 'react-router-dom';
import { Button, Card, CardContent, CardHeader, CardTitle } from '@scb/ui';
import {
  offeringPackagesQueryKey,
  useOfferingPackages,
  type PackageResponse,
} from '../../api/endpoints';
import { listItems } from '../shared/api-utils';
import { Money } from '../shared/Money';
import { usePortalSettings } from '../shared/extras';
import { AddToCartButton } from '../cart/AddToCartButton';

/**
 * Booking options a customer can buy for a given offering: a single session and
 * any multi-session packs. Rendered on the offering and session pages.
 */
export function OfferingPacks({
  offeringId,
  offeringName,
  dropInPrice,
  creditCost,
}: {
  offeringId: string;
  offeringName?: string;
  dropInPrice?: number | null;
  creditCost?: number | null;
}) {
  const settings = usePortalSettings();
  const query = useOfferingPackages(offeringId, {
    query: { queryKey: offeringPackagesQueryKey(offeringId), enabled: Boolean(offeringId) },
  });
  const packs = listItems<PackageResponse>(query);

  const hasDropIn = typeof dropInPrice === 'number' && dropInPrice > 0;
  const singleNote = hasDropIn
    ? 'Book one session'
    : creditCost && creditCost > 0
      ? `Book with ${creditCost} session${creditCost === 1 ? '' : 's'}`
      : 'Book with your sessions';

  return (
    <Card>
      <CardHeader>
        <CardTitle>Sessions</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <p className="text-sm text-muted-foreground">
          Book a single session, or buy a pack up front and save.
        </p>
        <ul className="flex flex-col gap-3">
          <li className="flex flex-wrap items-center justify-between gap-3 rounded-md border border-border p-3">
            <div className="flex flex-col">
              <span className="font-medium">Single session</span>
              <span className="text-xs text-muted-foreground">{singleNote}</span>
            </div>
            <div className="flex items-center gap-3">
              {hasDropIn ? <Money amountMinor={dropInPrice} className="font-semibold" /> : null}
              <Button asChild variant="outline" size="sm">
                <Link to={`/offerings/${offeringId}/schedule`}>Book now</Link>
              </Button>
            </div>
          </li>
          {packs.map((pack) => (
            <li
              key={pack.id}
              className="flex flex-wrap items-center justify-between gap-3 rounded-md border border-border p-3"
            >
              <div className="flex flex-col">
                <span className="font-medium">{pack.name}</span>
                <span className="text-xs text-muted-foreground">
                  {pack.credit_quantity} session{pack.credit_quantity === 1 ? '' : 's'}
                  {pack.validity_days ? ` · valid ${pack.validity_days} days` : ''}
                </span>
              </div>
              <div className="flex items-center gap-3">
                <Money amountMinor={pack.price} className="font-semibold" />
                <AddToCartButton
                  type="package"
                  refId={pack.id}
                  title={pack.name}
                  subtitle={offeringName}
                  priceMinor={pack.price}
                  currency={settings.currency}
                />
              </div>
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  );
}
