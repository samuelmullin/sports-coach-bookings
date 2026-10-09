import { Suspense, type ReactNode } from 'react';
import { lazyNamed, RouteFallback } from '@scb/ui';
import { Navigate, Route, Routes } from 'react-router-dom';
import { useStaffAuth } from './auth/staff-auth';
import { RequireAnonymous, RequireRole, RequireStaffAuth } from './auth/guards';
import { AdminLayout } from './layouts/AdminLayout';
import { ForbiddenPage } from './pages/ForbiddenPage';
import { NotFoundPage } from './pages/NotFoundPage';

const LoginPage = lazyNamed(() => import('./pages/auth/LoginPage'), 'LoginPage');
const ForgotPasswordPage = lazyNamed(
  () => import('./pages/auth/ForgotPasswordPage'),
  'ForgotPasswordPage',
);
const ResetPasswordPage = lazyNamed(
  () => import('./pages/auth/ResetPasswordPage'),
  'ResetPasswordPage',
);
const ConfirmEmailPage = lazyNamed(
  () => import('./pages/auth/ConfirmEmailPage'),
  'ConfirmEmailPage',
);
const AcceptInvitePage = lazyNamed(
  () => import('./pages/auth/AcceptInvitePage'),
  'AcceptInvitePage',
);
const SignupPage = lazyNamed(() => import('./pages/auth/SignupPage'), 'SignupPage');
const DashboardPage = lazyNamed(
  () => import('./features/dashboard/DashboardPage'),
  'DashboardPage',
);
const SettingsPage = lazyNamed(() => import('./features/settings/SettingsPage'), 'SettingsPage');
const TeamPage = lazyNamed(() => import('./features/team/TeamPage'), 'TeamPage');
const WebsitePage = lazyNamed(() => import('./features/website/WebsitePage'), 'WebsitePage');
const CatalogLayout = lazyNamed(() => import('./features/catalog/CatalogLayout'), 'CatalogLayout');
const VenuesPage = lazyNamed(() => import('./features/catalog/VenuesPage'), 'VenuesPage');
const OfferingsPage = lazyNamed(() => import('./features/catalog/OfferingsPage'), 'OfferingsPage');
const PackagesPage = lazyNamed(() => import('./features/catalog/PackagesPage'), 'PackagesPage');
const DiscountsPage = lazyNamed(() => import('./features/catalog/DiscountsPage'), 'DiscountsPage');
const PrivateSessionRequestsPage = lazyNamed(
  () => import('./features/catalog/PrivateSessionRequestsPage'),
  'PrivateSessionRequestsPage',
);
const PoliciesPage = lazyNamed(() => import('./features/policies/PoliciesPage'), 'PoliciesPage');
const PolicyEditorPage = lazyNamed(
  () => import('./features/policies/PolicyEditorPage'),
  'PolicyEditorPage',
);
const WaiversPage = lazyNamed(() => import('./features/waivers/WaiversPage'), 'WaiversPage');
const WaiverEditorPage = lazyNamed(
  () => import('./features/waivers/WaiverEditorPage'),
  'WaiverEditorPage',
);
const SchedulePage = lazyNamed(() => import('./features/schedule/SchedulePage'), 'SchedulePage');
const SessionDetailPage = lazyNamed(
  () => import('./features/schedule/SessionDetailPage'),
  'SessionDetailPage',
);
const CustomersPage = lazyNamed(
  () => import('./features/customers/CustomersPage'),
  'CustomersPage',
);
const CustomerDetailPage = lazyNamed(
  () => import('./features/customers/CustomerDetailPage'),
  'CustomerDetailPage',
);
const HouseholdDetailPage = lazyNamed(
  () => import('./features/customers/HouseholdDetailPage'),
  'HouseholdDetailPage',
);
const OrdersPage = lazyNamed(() => import('./features/orders/OrdersPage'), 'OrdersPage');
const OrderDetailPage = lazyNamed(
  () => import('./features/orders/OrderDetailPage'),
  'OrderDetailPage',
);
const OfflineOrderPage = lazyNamed(
  () => import('./features/orders/OfflineOrderPage'),
  'OfflineOrderPage',
);
const InventoryLayout = lazyNamed(
  () => import('./features/inventory/InventoryLayout'),
  'InventoryLayout',
);
const ProductsPage = lazyNamed(() => import('./features/inventory/ProductsPage'), 'ProductsPage');
const ProductEditorPage = lazyNamed(
  () => import('./features/inventory/ProductEditorPage'),
  'ProductEditorPage',
);
const StockPage = lazyNamed(() => import('./features/inventory/StockPage'), 'StockPage');
const FulfillmentPage = lazyNamed(
  () => import('./features/inventory/FulfillmentPage'),
  'FulfillmentPage',
);
const MessagingPage = lazyNamed(
  () => import('./features/messaging/MessagingPage'),
  'MessagingPage',
);
const MySessionsPage = lazyNamed(() => import('./features/coach/MySessionsPage'), 'MySessionsPage');
const SessionRosterPage = lazyNamed(
  () => import('./features/coach/SessionRosterPage'),
  'SessionRosterPage',
);
const CoachPlayersPage = lazyNamed(
  () => import('./features/coach/CoachPlayersPage'),
  'CoachPlayersPage',
);
const CoachPlayerDetailPage = lazyNamed(
  () => import('./features/coach/CoachPlayerDetailPage'),
  'CoachPlayerDetailPage',
);
const FeedbackHistoryPage = lazyNamed(
  () => import('./features/coach/FeedbackHistoryPage'),
  'FeedbackHistoryPage',
);

const ADMIN_ONLY: ('owner' | 'admin')[] = ['owner', 'admin'];
const COACH_ROLES: ('owner' | 'admin' | 'coach')[] = ['owner', 'admin', 'coach'];

function LandingRedirect() {
  const { role } = useStaffAuth();
  if (role === 'coach') return <Navigate to="/my-sessions" replace />;
  return <DashboardPage />;
}

function AdminOnly({ children }: { children: ReactNode }) {
  return <RequireRole roles={ADMIN_ONLY}>{children}</RequireRole>;
}

/** Owners/admins may also view the coach experience; coaches are the primary user. */
function CoachAccess({ children }: { children: ReactNode }) {
  return <RequireRole roles={COACH_ROLES}>{children}</RequireRole>;
}

function ForbiddenBoundary({ children }: { children: ReactNode }) {
  const { forbidden, clearForbidden } = useStaffAuth();
  if (forbidden) {
    return (
      <div className="p-4" onClick={clearForbidden}>
        <ForbiddenPage />
      </div>
    );
  }
  return <>{children}</>;
}

export function AppRoutes() {
  return (
    <Suspense fallback={<RouteFallback />}>
      <Routes>
        <Route
          path="/login"
          element={
            <RequireAnonymous>
              <LoginPage />
            </RequireAnonymous>
          }
        />
        <Route
          path="/signup"
          element={
            <RequireAnonymous>
              <SignupPage />
            </RequireAnonymous>
          }
        />
        <Route path="/forgot-password" element={<ForgotPasswordPage />} />
        <Route path="/reset-password" element={<ResetPasswordPage />} />
        <Route path="/confirm-email" element={<ConfirmEmailPage />} />
        <Route path="/accept-invite/:token" element={<AcceptInvitePage />} />

        <Route
          element={
            <RequireStaffAuth>
              <ForbiddenBoundary>
                <AdminLayout />
              </ForbiddenBoundary>
            </RequireStaffAuth>
          }
        >
          <Route index element={<LandingRedirect />} />
          <Route path="sessions" element={<Navigate to="/schedule" replace />} />
          <Route
            path="schedule"
            element={
              <AdminOnly>
                <SchedulePage />
              </AdminOnly>
            }
          />
          <Route
            path="schedule/:sessionId"
            element={
              <AdminOnly>
                <SessionDetailPage />
              </AdminOnly>
            }
          />
          <Route
            path="my-sessions"
            element={
              <CoachAccess>
                <MySessionsPage />
              </CoachAccess>
            }
          />
          <Route
            path="my-sessions/:sessionId"
            element={
              <CoachAccess>
                <SessionRosterPage />
              </CoachAccess>
            }
          />
          <Route
            path="players"
            element={
              <CoachAccess>
                <CoachPlayersPage />
              </CoachAccess>
            }
          />
          <Route
            path="players/:playerId"
            element={
              <CoachAccess>
                <CoachPlayerDetailPage />
              </CoachAccess>
            }
          />

          <Route
            path="customers"
            element={
              <AdminOnly>
                <CustomersPage />
              </AdminOnly>
            }
          />
          <Route
            path="customers/:customerId"
            element={
              <AdminOnly>
                <CustomerDetailPage />
              </AdminOnly>
            }
          />
          <Route
            path="households/:householdId"
            element={
              <AdminOnly>
                <HouseholdDetailPage />
              </AdminOnly>
            }
          />

          <Route
            path="orders"
            element={
              <AdminOnly>
                <OrdersPage />
              </AdminOnly>
            }
          />
          <Route
            path="orders/new"
            element={
              <AdminOnly>
                <OfflineOrderPage />
              </AdminOnly>
            }
          />
          <Route
            path="orders/:orderId"
            element={
              <AdminOnly>
                <OrderDetailPage />
              </AdminOnly>
            }
          />

          <Route
            path="catalog"
            element={
              <AdminOnly>
                <CatalogLayout />
              </AdminOnly>
            }
          >
            <Route index element={<Navigate to="venues" replace />} />
            <Route path="venues" element={<VenuesPage />} />
            <Route path="offerings" element={<OfferingsPage />} />
            <Route path="packages" element={<PackagesPage />} />
            <Route path="discounts" element={<DiscountsPage />} />
            <Route path="private-requests" element={<PrivateSessionRequestsPage />} />
          </Route>

          <Route
            path="policies"
            element={
              <AdminOnly>
                <PoliciesPage />
              </AdminOnly>
            }
          />
          <Route
            path="policies/:policyId"
            element={
              <AdminOnly>
                <PolicyEditorPage />
              </AdminOnly>
            }
          />

          <Route
            path="waivers"
            element={
              <AdminOnly>
                <WaiversPage />
              </AdminOnly>
            }
          />
          <Route
            path="waivers/:templateId"
            element={
              <AdminOnly>
                <WaiverEditorPage />
              </AdminOnly>
            }
          />

          <Route
            path="inventory"
            element={
              <AdminOnly>
                <InventoryLayout />
              </AdminOnly>
            }
          >
            <Route index element={<Navigate to="products" replace />} />
            <Route path="products" element={<ProductsPage />} />
            <Route path="products/:productId" element={<ProductEditorPage />} />
            <Route path="stock" element={<StockPage />} />
            <Route path="fulfillment" element={<FulfillmentPage />} />
          </Route>

          <Route
            path="messaging"
            element={
              <AdminOnly>
                <MessagingPage />
              </AdminOnly>
            }
          />

          <Route
            path="team"
            element={
              <AdminOnly>
                <TeamPage />
              </AdminOnly>
            }
          />
          <Route
            path="feedback"
            element={
              <CoachAccess>
                <FeedbackHistoryPage />
              </CoachAccess>
            }
          />
          <Route
            path="website"
            element={
              <AdminOnly>
                <WebsitePage />
              </AdminOnly>
            }
          />
          <Route
            path="settings"
            element={
              <AdminOnly>
                <SettingsPage />
              </AdminOnly>
            }
          />
          <Route path="*" element={<NotFoundPage />} />
        </Route>
      </Routes>
    </Suspense>
  );
}
