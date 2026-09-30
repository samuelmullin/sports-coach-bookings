/**
 * Readable aliases over the generated orval hooks.
 *
 * The generated names (`useSportsCoachBookingsWebPortal...`) are intentionally
 * verbose to avoid collisions across apps. Feature code imports short names
 * from here instead. No generated files are edited.
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------
export type { ErrorResponse } from '@scb/api-client';

export type {
  OfferingResponse,
  PackageResponse,
  VenueResponse,
  PlayerResponse,
  PlayerListResponse,
  PlayerRequest,
  PlayerProfileRequest,
  PlayerProfileResponse,
  MedicalInfoResponse,
  MedicalInfoRequest,
  EmergencyContactResponse,
  EmergencyContactRequest,
  EmergencyContactListResponse,
  AuthorizedPickupResponse,
  AuthorizedPickupRequest,
  AuthorizedPickupListResponse,
  PositionOptionResponse,
  PlayerWaiverStatusResponse,
  HouseholdWaiverStatusResponse,
  WaiverVersionResponse,
  SignWaiverRequest,
  WaiverSignatureResponse,
  WaiverPdfResponse,
  PolicySummaryResponse,
  PolicyOutcome,
} from '@scb/api-client';

export type {
  LegalDocumentResponse,
  LegalDocumentSummaryResponse,
  LegalDocumentListResponse,
  EmailDocumentRequest,
  EmailDocumentResponse,
} from '@scb/api-client';

export type { SportsCoachBookingsWebPortalScheduleSessionsControllerIndexParams as SessionIndexParams } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalScheduleSessionsControllerIndex200DataItem as SessionListItem } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalScheduleSessionsControllerShow200 as SessionDetail } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalScheduleSessionsControllerIndex200DataItemOffering as SessionOffering } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalScheduleSessionsControllerIndex200DataItemSession as SessionRecord } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalScheduleSessionsControllerIndex200DataItemVenue as SessionVenue } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalScheduleSessionsControllerIndex200DataItemCoachesItem as SessionCoach } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalScheduleSessionsControllerIndex200DataItemNotBookableReason as NotBookableReason } from '@scb/api-client';

export type { SportsCoachBookingsWebPortalInventoryProductsControllerIndex200DataItem as ProductSummary } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalInventoryProductsControllerIndex200DataItemVariantsItem as ProductVariant } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalInventoryProductsControllerShow200 as ProductDetail } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalInventoryPickupsControllerIndex200DataItem as Pickup } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalInventoryPickupsControllerIndex200DataItemStatus as PickupStatus } from '@scb/api-client';

export type { SportsCoachBookingsWebPortalReservationsReservationsControllerCreate201 as ReservationCreateResult } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalReservationsReservationsControllerShow200 as ReservationRecord } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalReservationsReservationsControllerShow200SessionsItem as ReservationSessionSummary } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalReservationsReservationsControllerShow200Status as ReservationRecordStatus } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalReservationsReservationsControllerExtend200 as ReservationExtendResult } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalReservationsReservationsControllerCreateBody as ReservationCreateBody } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalReservationsReservationsControllerConvertBody as ReservationConvertBody } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalReservationsReservationsControllerConvertBodyAssignmentsItem as ReservationAssignmentInput } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalReservationsReservationsControllerConvert200 as ReservationConvertResult } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalReservationsReservationsControllerConvert200BookingsItem as ConvertedBooking } from '@scb/api-client';

export type { SportsCoachBookingsWebPortalBookingsBookingsControllerIndex200DataItem as BookingListItem } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalBookingsBookingsControllerCreateBody as BookingCreateBody } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalBookingsBookingsControllerCreateBodyMethod as BookingMethod } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalBookingsBookingsControllerCancelPreview200 as CancelPreview } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalBookingsBookingsControllerCancelPreview200Outcome as CancelOutcome } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalBookingsBookingsControllerRebookOptions200 as RebookOptions } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalBookingsBookingsControllerRebookOptions200SessionsItem as RebookSession } from '@scb/api-client';

export type { SportsCoachBookingsWebPortalOrdersOrdersControllerIndex200DataItem as OrderSummary } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalOrdersOrdersControllerShow200 as OrderDetail } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalOrdersCheckoutControllerCreate201 as CheckoutResult } from '@scb/api-client';

export type { SportsCoachBookingsWebPortalCartCartControllerShow200 as Cart } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalCartCartControllerShow200LinesItem as CartLine } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalCartCartControllerShow200PricingAllOf as CartPricing } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalCartCartControllerShow200PricingAllOfLinesItem as CartPricingLine } from '@scb/api-client';

export type { SportsCoachBookingsWebPortalCreditsCreditsControllerShow200DataItem as CreditBalance } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalCreditsCreditsControllerLedger200DataItem as CreditLedgerEntry } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalCreditsCreditsControllerLots200DataItem as CreditLot } from '@scb/api-client';

export type { SportsCoachBookingsWebPortalHouseholdHouseholdControllerShow200 as Household } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalHouseholdHouseholdControllerShow200MembersItem as HouseholdMember } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalHouseholdHouseholdControllerInvites200DataItem as HouseholdInvite } from '@scb/api-client';

export type { SportsCoachBookingsWebPortalAccountAccountControllerShow200 as Account } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalAccountAccountControllerShow200CustomerUser as CustomerUser } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalAccountAccountControllerPreferences200 as NotificationPreferences } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalFeedbackFeedbackControllerIndex200DataItem as FeedbackEntry } from '@scb/api-client';

// ---------------------------------------------------------------------------
// Query hooks
// ---------------------------------------------------------------------------
export {
  useSportsCoachBookingsWebPortalCatalogOfferingsControllerIndex as useOfferings,
  useSportsCoachBookingsWebPortalCatalogOfferingsControllerPackages as useOfferingPackages,
  useSportsCoachBookingsWebPortalCatalogPackagesControllerIndex as usePackages,
  useSportsCoachBookingsWebPortalCatalogVenuesControllerIndex as useVenues,
} from '@scb/api-client';

export { useSportsCoachBookingsWebPortalScheduleSessionsControllerIndex as useSessions } from '@scb/api-client';
export { useSportsCoachBookingsWebPortalScheduleSessionsControllerShow as useSession } from '@scb/api-client';

export {
  useSportsCoachBookingsWebPortalInventoryProductsControllerIndex as useProducts,
  useSportsCoachBookingsWebPortalInventoryProductsControllerShow as useProduct,
  useSportsCoachBookingsWebPortalInventoryPickupsControllerIndex as usePickups,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebPortalPlayersPlayersControllerIndex as usePlayers,
  useSportsCoachBookingsWebPortalPlayersPlayersControllerShow as usePlayer,
  useSportsCoachBookingsWebPortalPlayersPositionOptionsControllerIndex as usePositionOptions,
  useSportsCoachBookingsWebPortalPlayersMedicalControllerShow as usePlayerMedical,
  useSportsCoachBookingsWebPortalPlayersEmergencyContactsControllerIndex as useEmergencyContacts,
  useSportsCoachBookingsWebPortalPlayersAuthorizedPickupsControllerIndex as useAuthorizedPickups,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebPortalWaiversWaiversControllerPlayerIndex as usePlayerWaivers,
  useSportsCoachBookingsWebPortalWaiversWaiversControllerStatus as useHouseholdWaiverStatus,
  useSportsCoachBookingsWebPortalWaiversWaiversControllerShowVersion as useWaiverVersion,
  useSportsCoachBookingsWebPortalWaiversWaiversControllerPdf as useWaiverPdf,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebPortalLegalDocumentsControllerIndex as usePortalDocuments,
  useSportsCoachBookingsWebPortalLegalDocumentsControllerShow as usePortalDocument,
} from '@scb/api-client';

export { useSportsCoachBookingsWebPortalFeedbackFeedbackControllerIndex as usePlayerFeedback } from '@scb/api-client';

export { useSportsCoachBookingsWebPortalPoliciesPoliciesControllerShow as useOfferingPolicy } from '@scb/api-client';

export {
  useSportsCoachBookingsWebPortalBookingsBookingsControllerIndex as useBookings,
  useSportsCoachBookingsWebPortalBookingsBookingsControllerCancelPreview as useCancelPreview,
  useSportsCoachBookingsWebPortalBookingsBookingsControllerRebookOptions as useRebookOptions,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebPortalOrdersOrdersControllerIndex as useOrders,
  useSportsCoachBookingsWebPortalOrdersOrdersControllerShow as useOrder,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebPortalCartCartControllerShow as useCart,
  useSportsCoachBookingsWebPortalCartCartControllerPrice as useCartPrice,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebPortalCreditsCreditsControllerShow as useCredits,
  useSportsCoachBookingsWebPortalCreditsCreditsControllerLedger as useCreditLedger,
  useSportsCoachBookingsWebPortalCreditsCreditsControllerLots as useCreditLots,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebPortalHouseholdHouseholdControllerShow as useHousehold,
  useSportsCoachBookingsWebPortalHouseholdHouseholdControllerInvites as useHouseholdInvites,
  useSportsCoachBookingsWebPortalHouseholdInvitesControllerShow as useHouseholdInvite,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebPortalAccountAccountControllerPreferences as useNotificationPreferences,
  useSportsCoachBookingsWebPortalAccountAccountControllerShow as useAccount,
} from '@scb/api-client';

export { useSportsCoachBookingsWebPortalBrandingControllerShow as useBranding } from '@scb/api-client';

// ---------------------------------------------------------------------------
// Mutation hooks
// ---------------------------------------------------------------------------
export {
  useSportsCoachBookingsWebPortalPlayersPlayersControllerCreate as useCreatePlayer,
  useSportsCoachBookingsWebPortalPlayersPlayersControllerUpdate2 as useUpdatePlayer,
  useSportsCoachBookingsWebPortalPlayersPlayersControllerArchive as useArchivePlayer,
  useSportsCoachBookingsWebPortalPlayersPlayersControllerUpdateProfile as useUpdatePlayerProfile,
  useSportsCoachBookingsWebPortalPlayersMedicalControllerUpdate as useUpdatePlayerMedical,
  useSportsCoachBookingsWebPortalPlayersEmergencyContactsControllerCreate as useCreateEmergencyContact,
  useSportsCoachBookingsWebPortalPlayersEmergencyContactsControllerUpdate2 as useUpdateEmergencyContact,
  useSportsCoachBookingsWebPortalPlayersEmergencyContactsControllerDelete as useDeleteEmergencyContact,
  useSportsCoachBookingsWebPortalPlayersAuthorizedPickupsControllerCreate as useCreateAuthorizedPickup,
  useSportsCoachBookingsWebPortalPlayersAuthorizedPickupsControllerUpdate2 as useUpdateAuthorizedPickup,
  useSportsCoachBookingsWebPortalPlayersAuthorizedPickupsControllerDelete as useDeleteAuthorizedPickup,
} from '@scb/api-client';

export { useSportsCoachBookingsWebPortalWaiversWaiversControllerSign as useSignWaiver } from '@scb/api-client';

export {
  useSportsCoachBookingsWebPortalLegalDocumentsControllerEmail as useEmailPortalDocument,
  useSportsCoachBookingsWebPortalWaiversWaiversControllerEmailVersion as useEmailWaiverVersion,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebPortalBookingsBookingsControllerCreate as useCreateBooking,
  useSportsCoachBookingsWebPortalBookingsBookingsControllerCancel as useCancelBooking,
  useSportsCoachBookingsWebPortalBookingsBookingsControllerRebook as useRebookBooking,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebPortalCartCartControllerAddLine as useAddCartLine,
  useSportsCoachBookingsWebPortalCartCartControllerUpdateLine as useUpdateCartLine,
  useSportsCoachBookingsWebPortalCartCartControllerRemoveLine as useRemoveCartLine,
  useSportsCoachBookingsWebPortalCartCartControllerApplyDiscount as useApplyDiscount,
  useSportsCoachBookingsWebPortalCartCartControllerRemoveDiscount as useRemoveDiscount,
} from '@scb/api-client';

export { useSportsCoachBookingsWebPortalOrdersCheckoutControllerCreate as useCheckout } from '@scb/api-client';

export {
  useSportsCoachBookingsWebPortalReservationsReservationsControllerCreate as useCreateReservation,
  useSportsCoachBookingsWebPortalReservationsReservationsControllerShow as useReservationResource,
  useSportsCoachBookingsWebPortalReservationsReservationsControllerExtend as useExtendReservation,
  useSportsCoachBookingsWebPortalReservationsReservationsControllerDelete as useReleaseReservation,
  useSportsCoachBookingsWebPortalReservationsReservationsControllerConvert as useConvertReservation,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebPortalHouseholdHouseholdControllerInvite as useInviteHouseholdMember,
  useSportsCoachBookingsWebPortalHouseholdHouseholdControllerRemoveMember as useRemoveHouseholdMember,
  useSportsCoachBookingsWebPortalHouseholdHouseholdControllerTransferPrimary as useTransferPrimary,
  useSportsCoachBookingsWebPortalHouseholdHouseholdControllerLeave as useLeaveHousehold,
} from '@scb/api-client';

export { useSportsCoachBookingsWebPortalHouseholdInvitesControllerAccept as useAcceptHouseholdInvite } from '@scb/api-client';

export {
  useSportsCoachBookingsWebPortalAccountAccountControllerUpdate2 as useUpdateAccount,
  useSportsCoachBookingsWebPortalAccountAccountControllerUpdateEmail as useUpdateEmail,
  useSportsCoachBookingsWebPortalAccountAccountControllerUpdatePassword as useUpdatePassword,
  useSportsCoachBookingsWebPortalAccountAccountControllerUpdatePreferences as useUpdateNotificationPreferences,
  useSportsCoachBookingsWebPortalAccountPurchaseGuardControllerShow as usePurchaseGuard,
} from '@scb/api-client';

// ---------------------------------------------------------------------------
// URL + query key helpers
// ---------------------------------------------------------------------------
export {
  getSportsCoachBookingsWebPortalWaiversWaiversControllerPdfUrl as waiverSignaturePdfUrl,
  getSportsCoachBookingsWebPortalPlayersMedicalControllerShowQueryKey as playerMedicalQueryKey,
  getSportsCoachBookingsWebPortalCreditsCreditsControllerShowQueryKey as creditsQueryKey,
  getSportsCoachBookingsWebPortalCreditsCreditsControllerLotsQueryKey as creditLotsQueryKey,
  getSportsCoachBookingsWebPortalCreditsCreditsControllerLedgerQueryKey as creditLedgerQueryKey,
  getSportsCoachBookingsWebPortalCartCartControllerShowQueryKey as cartQueryKey,
  getSportsCoachBookingsWebPortalBookingsBookingsControllerIndexQueryKey as bookingsQueryKey,
  getSportsCoachBookingsWebPortalHouseholdHouseholdControllerShowQueryKey as householdQueryKey,
  getSportsCoachBookingsWebPortalHouseholdHouseholdControllerInvitesQueryKey as householdInvitesQueryKey,
  getSportsCoachBookingsWebPortalScheduleSessionsControllerIndexQueryKey as sessionsQueryKey,
  getSportsCoachBookingsWebPortalScheduleSessionsControllerShowQueryKey as sessionQueryKey,
  getSportsCoachBookingsWebPortalOrdersOrdersControllerIndexQueryKey as ordersQueryKey,
  getSportsCoachBookingsWebPortalOrdersOrdersControllerShowQueryKey as orderQueryKey,
  getSportsCoachBookingsWebPortalPlayersPlayersControllerIndexQueryKey as playersQueryKey,
  getSportsCoachBookingsWebPortalInventoryProductsControllerIndexQueryKey as productsQueryKey,
  getSportsCoachBookingsWebPortalPlayersPlayersControllerShowQueryKey as playerQueryKey,
  getSportsCoachBookingsWebPortalPlayersEmergencyContactsControllerIndexQueryKey as emergencyContactsQueryKey,
  getSportsCoachBookingsWebPortalPlayersAuthorizedPickupsControllerIndexQueryKey as authorizedPickupsQueryKey,
  getSportsCoachBookingsWebPortalWaiversWaiversControllerPlayerIndexQueryKey as playerWaiversQueryKey,
  getSportsCoachBookingsWebPortalFeedbackFeedbackControllerIndexQueryKey as playerFeedbackQueryKey,
  getSportsCoachBookingsWebPortalHouseholdInvitesControllerShowQueryKey as householdInviteQueryKey,
  getSportsCoachBookingsWebPortalInventoryPickupsControllerIndexQueryKey as pickupsQueryKey,
  getSportsCoachBookingsWebPortalAccountAccountControllerShowQueryKey as accountQueryKey,
  getSportsCoachBookingsWebPortalAccountAccountControllerPreferencesQueryKey as notificationPreferencesQueryKey,
  getSportsCoachBookingsWebPortalCatalogOfferingsControllerPackagesQueryKey as offeringPackagesQueryKey,
  getSportsCoachBookingsWebPortalPoliciesPoliciesControllerShowQueryKey as policyQueryKey,
  getSportsCoachBookingsWebPortalInventoryProductsControllerShowQueryKey as productQueryKey,
  getSportsCoachBookingsWebPortalReservationsReservationsControllerShowQueryKey as reservationQueryKey,
  getSportsCoachBookingsWebPortalBookingsBookingsControllerCancelPreviewQueryKey as cancelPreviewQueryKey,
  getSportsCoachBookingsWebPortalBookingsBookingsControllerRebookOptionsQueryKey as rebookOptionsQueryKey,
  getSportsCoachBookingsWebPortalWaiversWaiversControllerShowVersionQueryKey as waiverVersionQueryKey,
  getSportsCoachBookingsWebPortalWaiversWaiversControllerPdfQueryKey as waiverPdfQueryKey,
  getSportsCoachBookingsWebPortalLegalDocumentsControllerIndexQueryKey as portalDocumentsQueryKey,
  getSportsCoachBookingsWebPortalLegalDocumentsControllerShowQueryKey as portalDocumentQueryKey,
} from '@scb/api-client';
