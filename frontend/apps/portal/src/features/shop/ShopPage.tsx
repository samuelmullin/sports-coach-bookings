import { Link } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { ShoppingBag } from 'lucide-react';
import { Badge, Card, CardContent, EmptyState } from '@scb/ui';
import { useProducts, type ProductSummary, type ProductVariant } from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { QueryState } from '../shared/QueryState';
import { PageHeader } from '../shared/PageHeader';
import { Money } from '../shared/Money';

const AVAILABILITY_VARIANT: Record<string, 'success' | 'warning' | 'danger'> = {
  'in stock': 'success',
  'low stock': 'warning',
  'sold out': 'danger',
};

export function StockBadge({ availability }: { availability: string }) {
  return (
    <Badge variant={AVAILABILITY_VARIANT[availability] ?? 'outline'}>
      {availability.charAt(0).toUpperCase() + availability.slice(1)}
    </Badge>
  );
}

export function lowestPrice(variants?: ProductVariant[] | null): number | undefined {
  if (!variants || variants.length === 0) return undefined;
  return Math.min(...variants.map((variant) => variant.price ?? 0));
}

export function ShopPage() {
  const { t } = useTranslation();
  const query = useProducts();
  const products = listItems<ProductSummary>(query);

  return (
    <div className="flex flex-col gap-4">
      <PageHeader title={t('nav.shop')} description={t('shop.subtitle')} />
      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {products.length === 0 ? (
          <EmptyState
            icon={<ShoppingBag className="h-8 w-8" />}
            title={t('empty.shop')}
            description="Merch will appear here when it is available."
          />
        ) : (
          <ul className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {products.map((product) => {
              const price = lowestPrice(product.variants);
              return (
                <li key={product.id}>
                  <Card>
                    <CardContent className="flex flex-col gap-2 pt-4">
                      {product.image_urls?.[0] ? (
                        <img
                          src={product.image_urls[0]}
                          alt={product.name}
                          className="h-40 w-full rounded-md object-cover"
                          loading="lazy"
                        />
                      ) : null}
                      <div className="flex items-start justify-between gap-2">
                        <h2 className="font-medium">{product.name}</h2>
                        <StockBadge availability={product.availability} />
                      </div>
                      {price != null ? (
                        <Money amountMinor={price} className="font-semibold" />
                      ) : null}
                      <Link
                        to={`/shop/${product.id}`}
                        className="text-sm font-medium text-primary hover:underline"
                      >
                        View product
                      </Link>
                    </CardContent>
                  </Card>
                </li>
              );
            })}
          </ul>
        )}
      </QueryState>
    </div>
  );
}
