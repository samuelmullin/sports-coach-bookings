import { MoneyDisplay } from '@scb/ui';
import { usePortalSettings } from './extras';

export function Money({ amountMinor, className }: { amountMinor: number; className?: string }) {
  const { currency } = usePortalSettings();
  return <MoneyDisplay amountMinor={amountMinor} currency={currency} className={className} />;
}
