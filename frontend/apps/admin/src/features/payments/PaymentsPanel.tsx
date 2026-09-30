import { ExternalLink } from 'lucide-react';
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Skeleton,
  useToast,
} from '@scb/ui';
import {
  usePaymentsConnect,
  useStartPaymentsOnboarding,
  type PaymentsConnect,
} from '../../api/endpoints';
import { body, errorMessage, responseData } from '../shared/api-utils';

function statusVariant(status: string | undefined) {
  if (status === 'enabled') return 'success' as const;
  if (status === 'pending') return 'warning' as const;
  if (status === 'restricted') return 'danger' as const;
  return 'outline' as const;
}

interface OnboardingResult {
  url: string;
}

export function PaymentsPanel() {
  const query = usePaymentsConnect();
  const onboarding = useStartPaymentsOnboarding();
  const { toast } = useToast();
  const connect = body<PaymentsConnect>(query);

  const startOnboarding = async () => {
    try {
      const result = await onboarding.mutateAsync({
        params: {
          return_url: `${window.location.origin}/admin/settings/payments`,
          refresh_url: `${window.location.origin}/admin/settings/payments`,
        },
      });
      const url = responseData<OnboardingResult>(result)?.url;
      if (url) window.location.assign(url);
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    }
  };

  if (query.isLoading) return <Skeleton className="h-48 w-full" />;

  const requirements = Object.entries(connect?.requirements ?? {});
  const connected = connect?.status === 'enabled';

  return (
    <div className="flex flex-col gap-4">
      <Card>
        <CardHeader className="flex-row items-center justify-between">
          <CardTitle>Payments provider</CardTitle>
          <Badge variant={statusVariant(connect?.status)}>
            {connect?.status ?? 'not connected'}
          </Badge>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          <dl className="grid gap-3 sm:grid-cols-2">
            <div>
              <dt className="text-xs text-muted-foreground">Provider</dt>
              <dd className="text-sm font-medium capitalize">{connect?.provider ?? 'Stripe'}</dd>
            </div>
            <div>
              <dt className="text-xs text-muted-foreground">Platform fee</dt>
              <dd className="text-sm font-medium">
                {((connect?.platform_fee_bps ?? 0) / 100).toFixed(2)}%
              </dd>
            </div>
            <div>
              <dt className="text-xs text-muted-foreground">Charges enabled</dt>
              <dd className="text-sm font-medium">{connect?.charges_enabled ? 'Yes' : 'No'}</dd>
            </div>
            <div>
              <dt className="text-xs text-muted-foreground">Payouts enabled</dt>
              <dd className="text-sm font-medium">{connect?.payouts_enabled ? 'Yes' : 'No'}</dd>
            </div>
          </dl>

          <div className="flex justify-start">
            <Button onClick={() => void startOnboarding()} disabled={onboarding.isPending}>
              <ExternalLink className="h-4 w-4" aria-hidden="true" />
              {connected ? 'Manage onboarding' : 'Start onboarding'}
            </Button>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Requirements due</CardTitle>
        </CardHeader>
        <CardContent>
          {requirements.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              No outstanding requirements. You can accept payments.
            </p>
          ) : (
            <ul className="flex flex-col gap-2">
              {requirements.map(([key, value]) => (
                <li key={key} className="rounded-md bg-amber-50 p-2 text-xs text-amber-900">
                  <span className="font-medium">{key.replace(/_/g, ' ')}</span>
                  {Array.isArray(value) ? `: ${value.join(', ')}` : ''}
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
