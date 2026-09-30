import { Navigate, Outlet, Route, Routes } from 'react-router-dom';
import { RequireAnonymous, RequireCustomerAuth } from './auth/guards';
import { PortalLayout } from './layouts/PortalLayout';
import { HomePage } from './features/home/HomePage';
import { SchedulePage } from './features/catalog/SchedulePage';
import { SessionDetailPage } from './features/catalog/SessionDetailPage';
import { OfferingDetailPage } from './features/catalog/OfferingDetailPage';
import { PackagesPage } from './features/catalog/PackagesPage';
import { PackageDetailPage } from './features/catalog/PackageDetailPage';
import { ShopPage } from './features/shop/ShopPage';
import { ProductDetailPage } from './features/shop/ProductDetailPage';
import { AccountPage } from './features/account/AccountPage';
import { HouseholdPage } from './features/household/HouseholdPage';
import { PlayersPage } from './features/players/PlayersPage';
import { PlayerDetailPage } from './features/players/PlayerDetailPage';
import { WaiverSignPage } from './features/waivers/WaiverSignPage';
import { BookingsPage } from './features/bookings/BookingsPage';
import { BookingFlowPage } from './features/bookings/BookingFlowPage';
import { OfferingScheduleRoute } from './features/reservations/OfferingScheduleRoute';
import { ReservationCompletePage } from './features/reservations/ReservationCompletePage';
import { OrdersPage } from './features/orders/OrdersPage';
import { OrderDetailPage } from './features/orders/OrderDetailPage';
import { CreditsPage } from './features/credits/CreditsPage';
import { CartPage } from './features/cart/CartPage';
import { CheckoutReturnPage } from './features/cart/CheckoutReturnPage';
import { PickupsPage } from './features/pickups/PickupsPage';
import { PortalLoginPage } from './pages/auth/PortalLoginPage';
import { RegisterPage } from './pages/auth/RegisterPage';
import { PortalForgotPasswordPage } from './pages/auth/PortalForgotPasswordPage';
import { PortalResetPasswordPage } from './pages/auth/PortalResetPasswordPage';
import { PortalConfirmEmailPage } from './pages/auth/PortalConfirmEmailPage';
import { AcceptHouseholdInvitePage } from './pages/auth/AcceptHouseholdInvitePage';

export function AppRoutes() {
  return (
    <Routes>
      <Route element={<PortalLayout />}>
        <Route index element={<HomePage />} />
        <Route path="schedule" element={<SchedulePage />} />
        <Route path="sessions/:sessionId" element={<SessionDetailPage />} />
        <Route path="offerings/:offeringId" element={<OfferingDetailPage />} />
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
  );
}
