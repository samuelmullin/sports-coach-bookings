import { Card, CardContent, CardHeader, CardTitle } from '@scb/ui';
import { useStaffAuth } from '../../auth/staff-auth';
import { useBookings, useCustomers, useSessions } from '../../api/endpoints';
import { listItems } from '../shared/api-utils';
import { OnboardingChecklist } from './OnboardingChecklist';

export function DashboardPage() {
  const { membership, role, staffUser } = useStaffAuth();
  const sessions = listItems(useSessions({}));
  const bookings = listItems(useBookings({}));
  const customers = listItems(useCustomers({}));

  const stats = [
    { label: 'Upcoming sessions', value: sessions.length },
    { label: 'Bookings', value: bookings.length },
    { label: 'Customers', value: customers.length },
  ];

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold">{membership?.tenant?.name}</h1>
        <p className="text-sm text-muted-foreground">
          Signed in as {staffUser?.email} ({role})
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {stats.map((stat) => (
          <Card key={stat.label}>
            <CardHeader>
              <CardTitle>{stat.label}</CardTitle>
            </CardHeader>
            <CardContent className="text-2xl font-semibold">{stat.value}</CardContent>
          </Card>
        ))}
      </div>

      <OnboardingChecklist />
    </div>
  );
}
