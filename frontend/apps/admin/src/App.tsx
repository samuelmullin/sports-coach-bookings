import type { ReactNode } from 'react';
import { Navigate, Route, Routes } from 'react-router-dom';
import { useStaffAuth } from './auth/staff-auth';
import { RequireAnonymous, RequireRole, RequireStaffAuth } from './auth/guards';
import { AdminLayout } from './layouts/AdminLayout';
import { ForbiddenPage } from './pages/ForbiddenPage';
import { NotFoundPage } from './pages/NotFoundPage';
import { LoginPage } from './pages/auth/LoginPage';
import { ForgotPasswordPage } from './pages/auth/ForgotPasswordPage';
import { ResetPasswordPage } from './pages/auth/ResetPasswordPage';
import { ConfirmEmailPage } from './pages/auth/ConfirmEmailPage';
import { AcceptInvitePage } from './pages/auth/AcceptInvitePage';
import { SignupPage } from './pages/auth/SignupPage';
import { DashboardPage } from './features/dashboard/DashboardPage';
import { SettingsPage } from './features/settings/SettingsPage';
import { TeamPage } from './features/team/TeamPage';
import { CatalogLayout } from './features/catalog/CatalogLayout';
import { VenuesPage } from './features/catalog/VenuesPage';
import { OfferingsPage } from './features/catalog/OfferingsPage';
import { PackagesPage } from './features/catalog/PackagesPage';
import { DiscountsPage } from './features/catalog/DiscountsPage';
import { PoliciesPage } from './features/policies/PoliciesPage';
import { PolicyEditorPage } from './features/policies/PolicyEditorPage';
import { WaiversPage } from './features/waivers/WaiversPage';
import { WaiverEditorPage } from './features/waivers/WaiverEditorPage';
import { SchedulePage } from './features/schedule/SchedulePage';
import { SessionDetailPage } from './features/schedule/SessionDetailPage';
import { CustomersPage } from './features/customers/CustomersPage';
import { CustomerDetailPage } from './features/customers/CustomerDetailPage';
import { HouseholdDetailPage } from './features/customers/HouseholdDetailPage';
import { OrdersPage } from './features/orders/OrdersPage';
import { OrderDetailPage } from './features/orders/OrderDetailPage';
import { OfflineOrderPage } from './features/orders/OfflineOrderPage';
import { InventoryLayout } from './features/inventory/InventoryLayout';
import { ProductsPage } from './features/inventory/ProductsPage';
import { ProductEditorPage } from './features/inventory/ProductEditorPage';
import { StockPage } from './features/inventory/StockPage';
import { FulfillmentPage } from './features/inventory/FulfillmentPage';
import { MessagingPage } from './features/messaging/MessagingPage';
import { MySessionsPage } from './features/coach/MySessionsPage';
import { SessionRosterPage } from './features/coach/SessionRosterPage';
import { CoachPlayersPage } from './features/coach/CoachPlayersPage';
import { CoachPlayerDetailPage } from './features/coach/CoachPlayerDetailPage';
import { FeedbackHistoryPage } from './features/coach/FeedbackHistoryPage';

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
  );
}
