import { Card, CardContent, CardHeader, CardTitle } from '@scb/ui';
import { useStaffAuth } from '../auth/staff-auth';

export function DashboardPage() {
  const { membership, role, staffUser } = useStaffAuth();
  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold">{membership?.tenant?.name}</h1>
        <p className="text-sm text-muted-foreground">
          Signed in as {staffUser?.email} ({role})
        </p>
      </div>
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <Card>
          <CardHeader>
            <CardTitle>Today&apos;s sessions</CardTitle>
          </CardHeader>
          <CardContent className="text-2xl font-semibold">0</CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>Active players</CardTitle>
          </CardHeader>
          <CardContent className="text-2xl font-semibold">0</CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>Pending orders</CardTitle>
          </CardHeader>
          <CardContent className="text-2xl font-semibold">0</CardContent>
        </Card>
      </div>
    </div>
  );
}
