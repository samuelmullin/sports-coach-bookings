/**
 * Readable aliases over the generated orval hooks.
 *
 * The generated names (`useSportsCoachBookingsWebStaff...`) are intentionally
 * verbose to avoid collisions across apps. Feature code imports short names
 * from here instead. No generated files are edited.
 */

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------
export type { ErrorResponse } from '@scb/api-client';
export type {
  VenueRequest,
  VenueResponse,
  OfferingRequest,
  OfferingResponse,
  PackageRequest,
  PackageResponse,
  DiscountRequest,
  DiscountResponse,
  TaxRateRequest,
  TaxRateResponse,
  PolicyRequest,
  PolicyResponse,
  PolicyRules,
  PolicyRulesCancellationTiersItem,
  PolicyOutcome,
  PolicySimulationRequest,
  PolicySimulationResponse,
  WaiverTemplateRequest,
  WaiverTemplateResponse,
  WaiverVersionRequest,
  WaiverVersionResponse,
  WaiverSignatureResponse,
  MedicalInfoResponse,
  HouseholdWaiverStatusResponse,
} from '@scb/api-client';
export type { SportsCoachBookingsWebStaffScheduleSessionsControllerIndexParams as SessionIndexParams } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffScheduleSessionsControllerIndex200DataItem as SessionSummary } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffScheduleSessionsControllerShow200 as SessionDetail } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffBookingsBookingsControllerCreateBodyMethod as BookingMethod } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffBookingsBookingsControllerIndex200DataItem as BookingListItem } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffBookingsBookingsControllerRoster200DataItem as RosterEntry } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffCustomersCustomersControllerIndex200DataItem as CustomerSummary } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffCustomersHouseholdsControllerShow200 as HouseholdDetail } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffCustomersHouseholdsControllerShow200MembersItem as HouseholdMember } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffOrdersOrdersControllerShow200 as OrderDetail } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffOrdersOrdersControllerShow200LinesItem as OrderLine } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffOrdersOrdersControllerCreateOfflineBodyLinesItemType as OfflineLineType } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffCreditsCreditsControllerShow200DataItem as CreditBalance } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffCreditsCreditsControllerLedger200DataItem as CreditLedgerEntry } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffNotificationsDeliveriesControllerIndex200DataItem as EmailDelivery } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffInventoryProductsControllerIndex200DataItem as ProductSummary } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffInventoryVariantsControllerIndex200DataItem as VariantSummary } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffInventoryStockControllerIndex200DataItem as StockLevel } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffInventoryStockControllerMovements200DataItem as StockMovement } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffInventoryFulfillmentsControllerIndex200DataItem as Fulfillment } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffInventoryFulfillmentsControllerIndex200DataItemStatus as FulfillmentStatus } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffTeamMembersControllerIndex200DataItem as TeamMember } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffTeamMembersControllerInvites200DataItem as TeamInvite } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffWaiversSignaturesControllerIndexParams as WaiverSignatureParams } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffPaymentsConnectControllerShow200 as PaymentsConnect } from '@scb/api-client';
export type { SportsCoachBookingsWebPortalBrandingControllerShow200 as Branding } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffSettingsBrandingControllerCreateUpload201 as BrandingUpload } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffInventoryUploadsControllerCreate201 as InventoryUpload } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffSettingsSettingsControllerShow200 as TenantSettings } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffBookingsPrivateSessionRequestsControllerIndexParams as PrivateSessionRequestParams } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffWebsitesSiteControllerShow200 as WebsiteSite } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffWebsitesContactSubmissionsControllerIndex200DataItem as WebsiteContactSubmission } from '@scb/api-client';
export type { SportsCoachBookingsWebStaffWebsitesSiteControllerCreateUpload201 as WebsiteUpload } from '@scb/api-client';

// ---------------------------------------------------------------------------
// Query hooks
// ---------------------------------------------------------------------------
export { useSportsCoachBookingsWebPortalBrandingControllerShow as useBranding } from '@scb/api-client';

export {
  useSportsCoachBookingsWebStaffSettingsSettingsControllerShow as useSettings,
  useSportsCoachBookingsWebStaffSettingsSettingsControllerUpdate2 as useUpdateSettings,
  useSportsCoachBookingsWebStaffSettingsSettingsControllerDelete as useDeleteTenant,
  useSportsCoachBookingsWebStaffSettingsSettingsControllerTransferOwnership as useTransferOwnership,
  useSportsCoachBookingsWebStaffSettingsBrandingControllerUpdate2 as useUpdateBranding,
  useSportsCoachBookingsWebStaffSettingsBrandingControllerCreateUpload as useCreateBrandingUpload,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebStaffWebsitesSiteControllerShow as useWebsiteSite,
  useSportsCoachBookingsWebStaffWebsitesSiteControllerUpdate2 as useUpdateWebsiteSite,
  useSportsCoachBookingsWebStaffWebsitesSiteControllerPublish as usePublishWebsiteSite,
  useSportsCoachBookingsWebStaffWebsitesSiteControllerCreateUpload as useCreateWebsiteUpload,
  useSportsCoachBookingsWebStaffWebsitesContactSubmissionsControllerIndex as useWebsiteContacts,
  useSportsCoachBookingsWebStaffWebsitesContactSubmissionsControllerUpdate as useUpdateWebsiteContact,
  getSportsCoachBookingsWebStaffWebsitesContactSubmissionsControllerIndexQueryKey as websiteContactsQueryKey,
  getSportsCoachBookingsWebStaffWebsitesSiteControllerShowQueryKey as websiteSiteQueryKey,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebStaffTeamMembersControllerIndex as useTeam,
  useSportsCoachBookingsWebStaffTeamMembersControllerInvites as useTeamInvites,
  useSportsCoachBookingsWebStaffTeamMembersControllerInvite as useInviteTeamMember,
  useSportsCoachBookingsWebStaffTeamMembersControllerUpdate2 as useUpdateTeamMember,
  useSportsCoachBookingsWebStaffTeamMembersControllerDelete as useRemoveTeamMember,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebStaffPaymentsConnectControllerShow as usePaymentsConnect,
  useSportsCoachBookingsWebStaffPaymentsConnectControllerOnboarding as useStartPaymentsOnboarding,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebStaffCatalogVenuesControllerIndex as useVenues,
  useSportsCoachBookingsWebStaffCatalogVenuesControllerShow as useVenue,
  useSportsCoachBookingsWebStaffCatalogVenuesControllerCreate as useCreateVenue,
  useSportsCoachBookingsWebStaffCatalogVenuesControllerUpdate2 as useUpdateVenue,
  useSportsCoachBookingsWebStaffCatalogVenuesControllerArchive as useArchiveVenue,
  useSportsCoachBookingsWebStaffCatalogOfferingsControllerIndex as useOfferings,
  useSportsCoachBookingsWebStaffCatalogOfferingsControllerShow as useOffering,
  useSportsCoachBookingsWebStaffCatalogOfferingsControllerCreate as useCreateOffering,
  useSportsCoachBookingsWebStaffCatalogOfferingsControllerUpdate2 as useUpdateOffering,
  useSportsCoachBookingsWebStaffCatalogOfferingsControllerArchive as useArchiveOffering,
  useSportsCoachBookingsWebStaffCatalogOfferingsControllerReorder as useReorderOfferings,
  useSportsCoachBookingsWebStaffCatalogPackagesControllerIndex as usePackages,
  useSportsCoachBookingsWebStaffCatalogPackagesControllerShow as usePackage,
  useSportsCoachBookingsWebStaffCatalogPackagesControllerCreate as useCreatePackage,
  useSportsCoachBookingsWebStaffCatalogPackagesControllerUpdate2 as useUpdatePackage,
  useSportsCoachBookingsWebStaffCatalogPackagesControllerArchive as useArchivePackage,
  useSportsCoachBookingsWebStaffCatalogPackagesControllerSetOfferings as useSetPackageOfferings,
  useSportsCoachBookingsWebStaffCatalogDiscountsControllerIndex as useDiscounts,
  useSportsCoachBookingsWebStaffCatalogDiscountsControllerShow as useDiscount,
  useSportsCoachBookingsWebStaffCatalogDiscountsControllerCreate as useCreateDiscount,
  useSportsCoachBookingsWebStaffCatalogDiscountsControllerUpdate2 as useUpdateDiscount,
  useSportsCoachBookingsWebStaffCatalogDiscountsControllerArchive as useArchiveDiscount,
  useSportsCoachBookingsWebStaffCatalogDiscountsControllerValidate as useValidateDiscount,
  useSportsCoachBookingsWebStaffCatalogTaxRatesControllerIndex as useTaxRates,
  useSportsCoachBookingsWebStaffCatalogTaxRatesControllerCreate as useCreateTaxRate,
  useSportsCoachBookingsWebStaffCatalogTaxRatesControllerUpdate2 as useUpdateTaxRate,
  useSportsCoachBookingsWebStaffCatalogTaxRatesControllerArchive as useArchiveTaxRate,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebStaffPoliciesPoliciesControllerIndex as usePolicies,
  useSportsCoachBookingsWebStaffPoliciesPoliciesControllerShow as usePolicy,
  useSportsCoachBookingsWebStaffPoliciesPoliciesControllerCreate as useCreatePolicy,
  useSportsCoachBookingsWebStaffPoliciesPoliciesControllerUpdate2 as useUpdatePolicy,
  useSportsCoachBookingsWebStaffPoliciesPoliciesControllerArchive as useArchivePolicy,
  useSportsCoachBookingsWebStaffPoliciesPoliciesControllerAssign as useAssignPolicy,
  useSportsCoachBookingsWebStaffPoliciesPoliciesControllerUnassign as useUnassignPolicy,
  useSportsCoachBookingsWebStaffPoliciesPoliciesControllerSetDefault as useSetDefaultPolicy,
  useSportsCoachBookingsWebStaffPoliciesPoliciesControllerSimulate as useSimulatePolicy,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebStaffScheduleSessionsControllerIndex as useSessions,
  useSportsCoachBookingsWebStaffScheduleSessionsControllerShow as useSession,
  useSportsCoachBookingsWebStaffScheduleSessionsControllerMySessions as useMySessions,
  useSportsCoachBookingsWebStaffScheduleSessionsControllerCreate as useCreateSession,
  useSportsCoachBookingsWebStaffScheduleSessionsControllerCreateSeries as useCreateSessionSeries,
  useSportsCoachBookingsWebStaffScheduleSessionsControllerEditSeries as useEditSessionSeries,
  useSportsCoachBookingsWebStaffScheduleSessionsControllerUpdate2 as useUpdateSession,
  useSportsCoachBookingsWebStaffScheduleSessionsControllerReschedule as useRescheduleSession,
  useSportsCoachBookingsWebStaffScheduleSessionsControllerCancel as useCancelSession,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebStaffBookingsPrivateSessionRequestsControllerIndex as usePrivateSessionRequests,
  useSportsCoachBookingsWebStaffBookingsPrivateSessionRequestsControllerUpdate as useReviewPrivateSessionRequest,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebStaffBookingsBookingsControllerIndex as useBookings,
  useSportsCoachBookingsWebStaffBookingsBookingsControllerShow as useBooking,
  useSportsCoachBookingsWebStaffBookingsBookingsControllerRoster as useBookingsRoster,
  useSportsCoachBookingsWebStaffBookingsBookingsControllerCreate as useCreateBooking,
  useSportsCoachBookingsWebStaffBookingsBookingsControllerCancel as useCancelBooking,
  useSportsCoachBookingsWebStaffBookingsBookingsControllerAttendance as useUpdateAttendance,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebStaffCustomersCustomersControllerIndex as useCustomers,
  useSportsCoachBookingsWebStaffCustomersCustomersControllerShow as useCustomer,
  useSportsCoachBookingsWebStaffCustomersCustomersControllerUpdate2 as useUpdateCustomer,
  useSportsCoachBookingsWebStaffCustomersCustomersControllerDeactivate as useDeactivateCustomer,
  useSportsCoachBookingsWebStaffCustomersCustomersControllerReactivate as useReactivateCustomer,
  useSportsCoachBookingsWebStaffCustomersCustomersControllerResetPassword as useResetCustomerPassword,
  useSportsCoachBookingsWebStaffCustomersHouseholdsControllerIndex as useHouseholds,
  useSportsCoachBookingsWebStaffCustomersHouseholdsControllerShow as useHousehold,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebStaffOrdersOrdersControllerIndex as useOrders,
  useSportsCoachBookingsWebStaffOrdersOrdersControllerShow as useOrder,
  useSportsCoachBookingsWebStaffOrdersOrdersControllerCreateOffline as useCreateOfflineOrder,
  useSportsCoachBookingsWebStaffOrdersOrdersControllerRefund as useRefundOrder,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebStaffCreditsCreditsControllerShow as useHouseholdCredits,
  useSportsCoachBookingsWebStaffCreditsCreditsControllerLedger as useHouseholdCreditLedger,
  useSportsCoachBookingsWebStaffCreditsCreditsControllerLots as useHouseholdCreditLots,
  useSportsCoachBookingsWebStaffCreditsCreditsControllerGrant as useGrantCredits,
  useSportsCoachBookingsWebStaffCreditsCreditsControllerAdjust as useAdjustCredits,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebStaffNotificationsDeliveriesControllerIndex as useDeliveries,
  useSportsCoachBookingsWebStaffNotificationsDeliveriesControllerResend as useResendDelivery,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebStaffInventoryProductsControllerIndex as useProducts,
  useSportsCoachBookingsWebStaffInventoryProductsControllerShow as useProduct,
  useSportsCoachBookingsWebStaffInventoryProductsControllerCreate as useCreateProduct,
  useSportsCoachBookingsWebStaffInventoryProductsControllerUpdate2 as useUpdateProduct,
  useSportsCoachBookingsWebStaffInventoryProductsControllerArchive as useArchiveProduct,
  useSportsCoachBookingsWebStaffInventoryProductsControllerReorder as useReorderProducts,
  useSportsCoachBookingsWebStaffInventoryVariantsControllerIndex as useVariants,
  useSportsCoachBookingsWebStaffInventoryVariantsControllerCreate as useCreateVariant,
  useSportsCoachBookingsWebStaffInventoryVariantsControllerUpdate2 as useUpdateVariant,
  useSportsCoachBookingsWebStaffInventoryVariantsControllerArchive as useArchiveVariant,
  useSportsCoachBookingsWebStaffInventoryStockControllerIndex as useStockLevels,
  useSportsCoachBookingsWebStaffInventoryStockControllerMovements as useStockMovements,
  useSportsCoachBookingsWebStaffInventoryStockControllerReceive as useReceiveStock,
  useSportsCoachBookingsWebStaffInventoryStockControllerAdjust as useAdjustStock,
  useSportsCoachBookingsWebStaffInventoryFulfillmentsControllerIndex as useFulfillments,
  useSportsCoachBookingsWebStaffInventoryFulfillmentsControllerReady as useMarkFulfillmentReady,
  useSportsCoachBookingsWebStaffInventoryFulfillmentsControllerPickup as useMarkFulfillmentPickedUp,
  useSportsCoachBookingsWebStaffInventoryUploadsControllerCreate as useCreateInventoryUpload,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebStaffWaiversTemplatesControllerIndex as useWaiverTemplates,
  useSportsCoachBookingsWebStaffWaiversTemplatesControllerShow as useWaiverTemplate,
  useSportsCoachBookingsWebStaffWaiversTemplatesControllerCreate as useCreateWaiverTemplate,
  useSportsCoachBookingsWebStaffWaiversTemplatesControllerUpdate2 as useUpdateWaiverTemplate,
  useSportsCoachBookingsWebStaffWaiversTemplatesControllerArchive as useArchiveWaiverTemplate,
  useSportsCoachBookingsWebStaffWaiversVersionsControllerIndex as useWaiverVersions,
  useSportsCoachBookingsWebStaffWaiversVersionsControllerPreview as useWaiverPreview,
  useSportsCoachBookingsWebStaffWaiversVersionsControllerCreate as useCreateWaiverVersion,
  useSportsCoachBookingsWebStaffWaiversVersionsControllerUpdate as useUpdateWaiverVersion,
  useSportsCoachBookingsWebStaffWaiversVersionsControllerPublish as usePublishWaiverVersion,
  useSportsCoachBookingsWebStaffWaiversSignaturesControllerIndex as useWaiverSignatures,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebStaffPlayersPlayersControllerIndex as usePlayers,
  useSportsCoachBookingsWebStaffPlayersMedicalControllerShow as usePlayerMedical,
} from '@scb/api-client';

export {
  getSportsCoachBookingsWebStaffWaiversSignaturesControllerPdfUrl as waiverSignaturePdfUrl,
  getSportsCoachBookingsWebStaffWaiversSignaturesControllerExportUrl as waiverSignaturesExportUrl,
  getSportsCoachBookingsWebStaffPlayersMedicalControllerShowQueryKey as playerMedicalQueryKey,
  getSportsCoachBookingsWebStaffCreditsCreditsControllerShowQueryKey as householdCreditsQueryKey,
  getSportsCoachBookingsWebStaffCustomersHouseholdsControllerShowQueryKey as householdQueryKey,
} from '@scb/api-client';

// ---------------------------------------------------------------------------
// Coach API (wp-15)
// ---------------------------------------------------------------------------
export type {
  SportsCoachBookingsWebStaffCoachCoachControllerIndex200DataItem as CoachSessionEntry,
  SportsCoachBookingsWebStaffCoachCoachControllerIndexParams as CoachSessionIndexParams,
  SportsCoachBookingsWebStaffCoachCoachControllerRoster200DataItem as CoachRosterEntry,
  SportsCoachBookingsWebStaffCoachCoachControllerPlayer200 as CoachPlayerResponse,
  SportsCoachBookingsWebStaffCoachCoachControllerAttendanceBody as CoachAttendanceBody,
  SportsCoachBookingsWebStaffFeedbackFeedbackControllerIndex200DataItem as CoachFeedbackRecord,
  SportsCoachBookingsWebStaffFeedbackFeedbackControllerIndexParams as CoachFeedbackIndexParams,
  SportsCoachBookingsWebStaffFeedbackFeedbackControllerCreateBody as CoachFeedbackCreateBody,
  SportsCoachBookingsWebStaffFeedbackFeedbackControllerUpdateBody as CoachFeedbackUpdateBody,
  SportsCoachBookingsWebStaffFeedbackFeedbackControllerSkillTags200DataItem as CoachSkillTag,
} from '@scb/api-client';

export {
  useSportsCoachBookingsWebStaffCoachCoachControllerIndex as useCoachSessions,
  useSportsCoachBookingsWebStaffCoachCoachControllerRoster as useCoachSessionRoster,
  useSportsCoachBookingsWebStaffCoachCoachControllerPlayer as useCoachPlayer,
  useSportsCoachBookingsWebStaffCoachCoachControllerAttendance as useMarkAttendance,
  useSportsCoachBookingsWebStaffFeedbackFeedbackControllerIndex as useFeedbackHistory,
  useSportsCoachBookingsWebStaffFeedbackFeedbackControllerShow as useFeedback,
  useSportsCoachBookingsWebStaffFeedbackFeedbackControllerCreate as useCreateFeedback,
  useSportsCoachBookingsWebStaffFeedbackFeedbackControllerUpdate as useUpdateFeedback,
  useSportsCoachBookingsWebStaffFeedbackFeedbackControllerShare as useShareFeedback,
  useSportsCoachBookingsWebStaffFeedbackFeedbackControllerRevisions as useFeedbackRevisions,
  useSportsCoachBookingsWebStaffFeedbackFeedbackControllerSkillTags as useSkillTags,
} from '@scb/api-client';

export {
  getSportsCoachBookingsWebStaffCoachCoachControllerIndexQueryKey as coachSessionsQueryKey,
  getSportsCoachBookingsWebStaffCoachCoachControllerIndexQueryOptions as coachSessionsQueryOptions,
  getSportsCoachBookingsWebStaffCoachCoachControllerRosterQueryKey as coachRosterQueryKey,
  getSportsCoachBookingsWebStaffCoachCoachControllerRosterQueryOptions as coachRosterQueryOptions,
  getSportsCoachBookingsWebStaffCoachCoachControllerPlayerQueryKey as coachPlayerQueryKey,
  getSportsCoachBookingsWebStaffFeedbackFeedbackControllerIndexQueryKey as feedbackHistoryQueryKey,
  getSportsCoachBookingsWebStaffFeedbackFeedbackControllerShowQueryKey as feedbackQueryKey,
} from '@scb/api-client';
