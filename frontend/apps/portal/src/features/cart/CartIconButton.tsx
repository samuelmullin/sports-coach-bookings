import { Link } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { ShoppingCart } from 'lucide-react';
import { useCartView } from './useCart';

/**
 * Header cart control: a cart icon with a badge showing the number of items.
 * A bundle/package line counts as a single item (and a session drop-in as one);
 * the badge reflects the same `itemCount` the cart page uses.
 */
export function CartIconButton() {
  const { t } = useTranslation();
  const { itemCount } = useCartView();
  const label = itemCount > 0 ? `${t('nav.cart')} (${itemCount})` : t('nav.cart');

  return (
    <Link
      to="/cart"
      aria-label={label}
      data-testid="cart-icon"
      className="relative rounded-md p-2 text-foreground hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
    >
      <ShoppingCart className="h-5 w-5" aria-hidden="true" />
      {itemCount > 0 ? (
        <span
          data-testid="cart-count"
          aria-hidden="true"
          className="absolute -right-0.5 -top-0.5 flex h-4 min-w-4 items-center justify-center rounded-full bg-primary px-1 text-[10px] font-semibold leading-none text-primary-foreground"
        >
          {itemCount > 99 ? '99+' : itemCount}
        </span>
      ) : null}
    </Link>
  );
}
