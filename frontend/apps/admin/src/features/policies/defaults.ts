import type { PolicyRules } from '../../api/endpoints';

export const defaultPolicyRules: PolicyRules = {
  cancellation_tiers: [
    { min_hours_before: 48, money_refund_pct: 100, credit_outcome: 'return' },
    { min_hours_before: 24, money_refund_pct: 0, credit_outcome: 'return' },
  ],
  late_cancel_counts_as_no_show: false,
  no_show: { money_refund_pct: 0, credit_outcome: 'forfeit' },
  provider_cancelled: { money_refund_pct: 100, credit_outcome: 'return' },
  rebook: {
    allowed: true,
    min_hours_before: 24,
    same_offering_only: false,
    max_rebooks_per_booking: null,
  },
};

export function summarizeRules(rules: PolicyRules): string {
  const tiers = [...rules.cancellation_tiers]
    .sort((a, b) => b.min_hours_before - a.min_hours_before)
    .map(
      (tier) =>
        `${tier.min_hours_before}h+: ${tier.money_refund_pct}% refund, sessions ${tier.credit_outcome}`,
    );
  const noShow = `No-show: sessions ${rules.no_show.credit_outcome}`;
  return [...tiers, noShow].join(' · ');
}
