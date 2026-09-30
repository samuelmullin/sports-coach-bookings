import { CheckCircle2, Circle } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@scb/ui';
import { Link } from 'react-router-dom';
import {
  useBranding,
  useOfferings,
  usePackages,
  usePaymentsConnect,
  usePolicies,
  useSessions,
  useVenues,
  useWaiverTemplates,
  type Branding,
  type PaymentsConnect,
} from '../../api/endpoints';
import { body, listItems } from '../shared/api-utils';

export interface OnboardingStep {
  key: string;
  label: string;
  to: string;
  done: boolean;
  detail?: string;
}

export function useOnboardingSteps(): { steps: OnboardingStep[]; complete: number; total: number } {
  const branding = body<Branding>(useBranding());
  const payments = body<PaymentsConnect>(usePaymentsConnect());
  const venues = listItems<unknown>(useVenues());
  const offerings = listItems<unknown>(useOfferings());
  const packages = listItems<unknown>(usePackages());
  const sessions = listItems<unknown>(useSessions({}));
  const waivers = listItems<unknown>(useWaiverTemplates());
  const policies = listItems<unknown>(usePolicies());

  const steps: OnboardingStep[] = [
    {
      key: 'branding',
      label: 'Brand your portal',
      to: '/settings?tab=branding',
      done: Boolean(branding?.theme?.primary_color),
    },
    {
      key: 'payments',
      label: 'Connect payments',
      to: '/settings?tab=payments',
      done: Boolean(payments?.charges_enabled),
      detail: payments?.status,
    },
    {
      key: 'venue',
      label: 'Add a venue',
      to: '/catalog/venues',
      done: venues.length > 0,
    },
    {
      key: 'offering',
      label: 'Create an offering',
      to: '/catalog/offerings',
      done: offerings.length > 0,
    },
    {
      key: 'package',
      label: 'Create a package',
      to: '/catalog/packages',
      done: packages.length > 0,
    },
    {
      key: 'session',
      label: 'Publish a session',
      to: '/schedule',
      done: sessions.length > 0,
    },
    {
      key: 'waiver',
      label: 'Add a waiver',
      to: '/waivers',
      done: waivers.length > 0,
    },
    {
      key: 'policy',
      label: 'Set a cancellation policy',
      to: '/policies',
      done: policies.length > 0,
    },
  ];

  return { steps, complete: steps.filter((step) => step.done).length, total: steps.length };
}

export function OnboardingChecklist() {
  const { steps, complete, total } = useOnboardingSteps();
  if (complete === total) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>You&apos;re all set up</CardTitle>
        </CardHeader>
        <CardContent className="text-sm text-muted-foreground">
          Every setup step is complete. Nice work!
        </CardContent>
      </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>
          Finish setting up ({complete}/{total})
        </CardTitle>
      </CardHeader>
      <CardContent>
        <ul className="flex flex-col gap-2">
          {steps.map((step) => (
            <li key={step.key}>
              <Link
                to={step.to}
                className="flex items-center gap-2 rounded-md p-2 text-sm hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              >
                {step.done ? (
                  <CheckCircle2 className="h-4 w-4 text-green-600" aria-hidden="true" />
                ) : (
                  <Circle className="h-4 w-4 text-muted-foreground" aria-hidden="true" />
                )}
                <span className={step.done ? 'text-muted-foreground line-through' : 'font-medium'}>
                  {step.label}
                </span>
                <span className="sr-only">{step.done ? 'complete' : 'incomplete'}</span>
              </Link>
            </li>
          ))}
        </ul>
      </CardContent>
    </Card>
  );
}
