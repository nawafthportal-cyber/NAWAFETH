# Changelog

All notable production-facing changes for the subscriptions, verification, badges, pricing, billing integrity, and provider plan experience are documented here.

## 2026-03-07 - Production Hardening Program (Phases 1-9)

### Phase 1 - Billing Integrity Hardening
- Added trusted payment confirmation fields and webhook idempotency support for invoices.
- Hardened payment webhooks with signature verification, event-id deduplication, amount/currency checks, and explicit rejection codes.
- Prevented unsafe manual paid/unpaid toggles for subscription and verification invoices in dashboard paths.
- Added reversal-aware lifecycle handling to revoke subscription/verification activation when payment is no longer effective.
- Added audit logging for sensitive billing state transitions.

Operational impact:
- Activation for paid subscription/verification flows now depends on trusted payment confirmation, not status toggles alone.

### Phase 2 - Provider-Only Access Enforcement
- Added central provider eligibility checks and applied them to subscription and verification entry points.
- Enforced provider-role/profile gates in permissions, serializer validation, and service entry logic.
- Preserved legacy compatibility for valid users that have provider profile data with stale role state.

Operational impact:
- Non-provider authenticated users can no longer subscribe/upgrade or initiate provider verification workflows.

### Phase 3 - Canonical Tier Normalization
- Introduced canonical tier domain (`basic`, `pioneer`, `professional`) with alias compatibility mapping.
- Unified tier resolution into a single helper layer while preserving legacy DB values and existing plan codes.
- Added compatibility fields in API responses to reduce client break risk.

Operational impact:
- Tier-dependent logic now resolves consistently across subscription, verification pricing, notifications, and dispatch.

### Phase 4 - Basic Plan Correction + Auto-Assignment
- Corrected Basic entitlement to free default provider tier.
- Added automatic Basic assignment on provider transition paths.
- Added safe backfill support for historical providers missing default entitlement.
- Updated effective-tier reads so free Basic fallback does not override valid paid upgrades.

Operational impact:
- Providers have deterministic baseline entitlement without corrupting paid subscription history.

### Phase 5 - One Current Subscription Rule
- Implemented runtime rule for one effective current subscription tier per provider.
- Added overlap normalization for ambiguous active/grace rows, preserving historical records.
- Added management command and data migration for safe cleanup of existing overlaps.

Operational impact:
- Current tier resolution is deterministic and stable for all downstream feature gates and pricing decisions.

### Phase 6 - Verification Pricing Correction
- Standardized verification pricing matrix by tier:
  - Basic: `100 SAR`
  - Pioneer: `50 SAR`
  - Professional: `0 SAR` (included)
- Changed verification billing to charge once per verification badge flow, not per requirement.
- Implemented explicit inclusive tax policy for verification pricing consistency across endpoint, summary, invoice, and payment.

Operational impact:
- Displayed verification price now matches billed amount and payment amount.

### Phase 7 - Verification Workflow + Badge Safety
- Made requirement attachments the authoritative evidence source.
- Added compatibility bridge from legacy document uploads into authoritative requirement attachments.
- Enforced approval/evidence/payment prerequisites before activation.
- Strengthened duplicate request prevention and badge-state revocation logic across pending/rejected/unpaid/reversed/expired states.

Operational impact:
- Badge activation and public visibility are tied to workflow truth and payment truth.

### Phase 8 - Provider Feature Gating
- Introduced centralized capability matrix by tier for:
  - competitive request timing
  - banner image limits
  - direct chat quota
  - promotional controls
  - support SLA metadata
  - reminder policy metadata
  - storage metadata / upload bridge
- Enforced key limits in backend paths (marketplace, messaging, promo).

Operational impact:
- Tier differences are backend-enforced for core operational controls, not UI-only.

### Phase 9 - Provider Subscription Cards + Summary Page
- Added centralized provider offer model for cards/summary rendering with Arabic-first labels and official annual prices.
- Updated provider-facing web and Flutter plan cards to consume backend offer payload.
- Added provider-facing summary page flow before subscription upgrade action.
- Updated subscription checkout to use canonical annual payable amount and annual activation window where applicable.

Operational impact:
- Provider sees consistent tier/pricing/capability messaging from backend truth on cards, summary, invoice, and upgrade flow.

---

## Data Safety Notes
- No destructive schema drops were introduced.
- Paid history was preserved through all phases.
- Added non-destructive, idempotent maintenance commands:
  - `seed_plans`
  - `backfill_provider_basic_entitlements`
  - `normalize_current_subscriptions`

