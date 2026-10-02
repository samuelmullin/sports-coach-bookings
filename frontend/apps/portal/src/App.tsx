import { Suspense } from 'react';
import { lazyNamed, RouteFallback } from '@scb/ui';
import { Navigate, Outlet, Route, Routes } from 'react-router-dom';
import { RequireAnonymous, RequireCustomerAuth } from './auth/guards';
import { PortalLayout } from './layouts/PortalLayout';

const HomePage = lazyNamed(() => import('./features/home/HomePage'), 'HomePage');
const SchedulePage = lazyNamed(() => import('./features/catalog/SchedulePage'), 'SchedulePage');
const SessionDetailPage = lazyNamed(
  () => import('./features/catalog/SessionDetailPage'),
  'SessionDetailPage',
);
const PackagesPage = lazyNamed(() => import('./features/catalog/PackagesPage'), 'PackagesPage');
const PackageDetailPage = lazyNamed(
  () => import('./features/catalog/PackageDetailPage'),
  'PackageDetailPage',
);
const ShopPage = lazyNamed(() => import('./features/shop/ShopPage'), 'ShopPage');
const ProductDetailPage = lazyNamed(
  () => import('./features/shop/ProductDetailPage'),
  'ProductDetailPage',
);
const AccountPage = lazyNamed(() => import('./features/account/AccountPage'), 'AccountPage');
const HouseholdPage = lazyNamed(
  () => import('./features/household/HouseholdPage'),
  'HouseholdPage',
);
const PlayersPage = lazyNamed(() => import('./features/players/PlayersPage'), 'PlayersPage');
const PlayerDetailPage = lazyNamed(
  () => import('./features/players/PlayerDetailPage'),
  'PlayerDetailPage',
);
const WaiverSignPage = lazyNamed(
  () => import('./features/waivers/WaiverSignPage'),
  'WaiverSignPage',
);
const BookingsPage = lazyNamed(() => import('./features/bookings/BookingsPage'), 'BookingsPage');
const BookingFlowPage = lazyNamed(
  () => import('./features/bookings/BookingFlowPage'),
  'BookingFlowPage',
);
const OfferingRedirect = lazyNamed(
  () => import('./features/reservations/OfferingScheduleRoute'),
  'OfferingRedirect',
);
const OfferingScheduleRoute = lazyNamed(
  () => import('./features/reservations/OfferingScheduleRoute'),
  'OfferingScheduleRoute',
);
const ReservationCompletePage = lazyNamed(
  () => import('./features/reservations/ReservationCompletePage'),
  'ReservationCompletePage',
);
const OrdersPage = lazyNamed(() => import('./features/orders/OrdersPage'), 'OrdersPage');
const OrderDetailPage = lazyNamed(
  () => import('./features/orders/OrderDetailPage'),
  'OrderDetailPage',
);
const CreditsPage = lazyNamed(() => import('./features/credits/CreditsPage'), 'CreditsPage');
const CartPage = lazyNamed(() => import('./features/cart/CartPage'), 'CartPage');
const CheckoutReturnPage = lazyNamed(
  () => import('./features/cart/CheckoutReturnPage'),
  'CheckoutReturnPage',
);
const PickupsPage = lazyNamed(() => import('./features/pickups/PickupsPage'), 'PickupsPage');
const PortalLoginPage = lazyNamed(() => import('./pages/auth/PortalLoginPage'), 'PortalLoginPage');
const RegisterPage = lazyNamed(() => import('./pages/auth/RegisterPage'), 'RegisterPage');
const PortalForgotPasswordPage = lazyNamed(
  () => import('./pages/auth/PortalForgotPasswordPage'),
  'PortalForgotPasswordPage',
);
const PortalResetPasswordPage = lazyNamed(
  () => import('./pages/auth/PortalResetPasswordPage'),
  'PortalResetPasswordPage',
);
const PortalConfirmEmailPage = lazyNamed(
  () => import('./pages/auth/PortalConfirmEmailPage'),
  'PortalConfirmEmailPage',
);
const AcceptHouseholdInvitePage = lazyNamed(
  () => import('./pages/auth/AcceptHouseholdInvitePage'),
  'AcceptHouseholdInvitePage',
);

export function AppRoutes() {
  return (
    <Suspense fallback={<RouteFallback />}>
      <Routes>
        <Route element={<PortalLayout />}>
          <Route index element={<HomePage />} />
          <Route path="schedule" element={<SchedulePage />} />
          <Route path="sessions/:sessionId" element={<SessionDetailPage />} />
          <Route path="offerings/:offeringId" element={<OfferingRedirect />} />
          <Route path="offerings/:offeringId/schedule" element={<OfferingScheduleRoute />} />
          <Route path="packages" element={<PackagesPage />} />
          <Route path="packages/:packageId" element={<PackageDetailPage />} />
          <Route path="shop" element={<ShopPage />} />
          <Route path="shop/:productId" element={<ProductDetailPage />} />
          <Route path="cart" element={<CartPage />} />
          <Route
            element={
              <RequireCustomerAuth>
                <Outlet />
              </RequireCustomerAuth>
            }
          >
            <Route path="account" element={<AccountPage />} />
            <Route path="household" element={<HouseholdPage />} />
            <Route path="players" element={<PlayersPage />} />
            <Route path="players/:playerId" element={<PlayerDetailPage />} />
            <Route path="players/:playerId/waivers/:versionId/sign" element={<WaiverSignPage />} />
            <Route path="bookings" element={<BookingsPage />} />
            <Route path="book/:sessionId" element={<BookingFlowPage />} />
            <Route path="reservations/:id/complete" element={<ReservationCompletePage />} />
            <Route path="orders" element={<OrdersPage />} />
            <Route path="orders/:orderId" element={<OrderDetailPage />} />
            <Route path="credits" element={<CreditsPage />} />
            <Route path="checkout/return" element={<CheckoutReturnPage />} />
            <Route path="pickups" element={<PickupsPage />} />
          </Route>
        </Route>

        <Route
          path="login"
          element={
            <RequireAnonymous>
              <PortalLoginPage />
            </RequireAnonymous>
          }
        />
        <Route path="register" element={<RegisterPage />} />
        <Route path="forgot-password" element={<PortalForgotPasswordPage />} />
        <Route path="reset-password" element={<PortalResetPasswordPage />} />
        <Route path="confirm-email" element={<PortalConfirmEmailPage />} />
        <Route path="accept-invite/:token" element={<AcceptHouseholdInvitePage />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </Suspense>
  );
}
