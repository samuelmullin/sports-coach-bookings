import { useMemo, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { ArrowLeft } from 'lucide-react';
import { Button, Card, CardContent } from '@scb/ui';
import { useProduct, productQueryKey, type ProductDetail } from '../../api/endpoints';
import { body, errorMessage } from '../shared/api-utils';
import { QueryState } from '../shared/QueryState';
import { PageHeader } from '../shared/PageHeader';
import { Money } from '../shared/Money';
import { usePortalSettings } from '../shared/extras';
import { AddToCartButton } from '../cart/AddToCartButton';
import { StockBadge } from './ShopPage';

function variantsToOptions(product: ProductDetail) {
  return (product.variants ?? []).map((variant) => ({
    id: variant.id ?? '',
    label:
      Object.entries(variant.option_values ?? {})
        .map(([key, value]) => `${key}: ${value}`)
        .join(' · ') || variant.sku,
    availability: variant.availability ?? 'in stock',
    price: variant.price ?? 0,
    soldOut: variant.availability === 'sold out',
  }));
}

export function ProductDetailPage() {
  const { productId } = useParams<{ productId: string }>();
  const settings = usePortalSettings();
  const query = useProduct(productId ?? '', {
    query: {
      queryKey: productQueryKey(productId ?? ''),
      enabled: Boolean(productId),
      retry: false,
    },
  });
  const product = body<ProductDetail>(query);
  const options = useMemo(() => (product ? variantsToOptions(product) : []), [product]);
  const [variantId, setVariantId] = useState<string | undefined>();
  const selected = options.find((option) => option.id === variantId) ?? options[0];

  return (
    <div className="flex flex-col gap-4">
      <Button asChild variant="ghost" size="sm" className="self-start">
        <Link to="/shop">
          <ArrowLeft className="h-4 w-4" aria-hidden="true" /> Back to shop
        </Link>
      </Button>

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {!product ? (
          <p className="text-sm text-muted-foreground">This product is not available.</p>
        ) : (
          <>
            <PageHeader
              title={product.name}
              description={product.description ?? undefined}
              actions={
                selected ? (
                  <AddToCartButton
                    type="product"
                    refId={selected.id}
                    disabled={selected.soldOut}
                    label={selected.soldOut ? 'Sold out' : 'Add to cart'}
                    title={product.name}
                    subtitle={selected.label}
                    priceMinor={selected.price}
                    currency={settings.currency}
                  />
                ) : (
                  <AddToCartButton
                    type="product"
                    refId={product.id}
                    disabled={product.availability === 'sold out'}
                    label={product.availability === 'sold out' ? 'Sold out' : 'Add to cart'}
                    title={product.name}
                    currency={settings.currency}
                  />
                )
              }
            />

            {product.image_urls?.length ? (
              <div className="flex gap-3 overflow-x-auto">
                {product.image_urls.map((url) => (
                  <img
                    key={url}
                    src={url}
                    alt={product.name}
                    className="h-56 w-auto rounded-md object-cover"
                    loading="lazy"
                  />
                ))}
              </div>
            ) : null}

            <div className="flex flex-wrap items-center gap-2">
              <StockBadge availability={selected?.availability ?? product.availability} />
              {selected ? (
                <Money amountMinor={selected.price} className="text-lg font-semibold" />
              ) : null}
            </div>

            {options.length > 0 ? (
              <Card>
                <CardContent className="flex flex-col gap-3 pt-4">
                  <h2 className="text-sm font-medium">Choose an option</h2>
                  <div className="flex flex-wrap gap-2">
                    {options.map((option) => (
                      <button
                        key={option.id}
                        type="button"
                        aria-pressed={(selected?.id ?? '') === option.id}
                        disabled={option.soldOut}
                        onClick={() => setVariantId(option.id)}
                        className={`rounded-md border px-3 py-2 text-sm ${
                          (selected?.id ?? '') === option.id
                            ? 'border-primary bg-primary text-primary-foreground'
                            : 'border-border hover:bg-muted'
                        } disabled:cursor-not-allowed disabled:opacity-50`}
                      >
                        {option.label}
                        {option.soldOut ? ' — sold out' : ''}
                      </button>
                    ))}
                  </div>
                </CardContent>
              </Card>
            ) : null}
          </>
        )}
      </QueryState>
    </div>
  );
}
