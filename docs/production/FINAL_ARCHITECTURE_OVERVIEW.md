# Final Architecture Overview (Production)

## 1) Domain Modules
- `apps/subscriptions`
  - canonical tier resolution
  - provider offer payload for cards/summary
  - default Basic entitlement
  - current subscription normalization
- `apps/verification`
  - request lifecycle
  - requirement/evidence model
  - verification pricing by tier
  - invoice generation and activation logic
  - badge sync and expiry handling
- `apps/billing`
  - invoice and payment attempts
  - trusted payment confirmation
  - signed webhook processing with idempotency
- `apps/subscriptions/capabilities.py`
  - centralized feature matrix by tier
  - backend gating helpers
- Enforcing consumers:
  - `apps/marketplace/api.py` (competitive request timing)
  - `apps/messaging/api.py` (direct chat quota)
  - `apps/promo/*` (promo controls + banner limits)
  - `apps/features/*` (capability exposure/support/upload bridge)

## 2) Runtime Control Flow

### Provider Onboarding
1. User transitions to provider (`ProviderProfile` created).
2. Basic free entitlement is ensured.
3. Historical providers can be repaired through backfill command.

### Subscription Upgrade
1. Provider reads plans from `/api/subscriptions/plans/` with `provider_offer`.
2. Provider opens summary and confirms.
3. Checkout creates pending subscription + invoice using canonical annual payable amount.
4. Trusted payment confirmation (webhook) activates subscription.
5. Current subscription normalization maintains one effective current tier.

### Verification
1. Provider creates request.
2. Evidence uploaded via requirement attachments (legacy docs mirrored for compatibility).
3. Admin approves/rejects requirements.
4. Finalize creates invoice once per verification badge flow.
5. Trusted payment (or free flow) activates verification and badge.
6. Reversal/refund/cancel/expiry revokes effective badge state.

## 3) Data Integrity Strategy
- Non-destructive migrations only.
- History preservation for paid subscriptions and invoices.
- Idempotent maintenance commands for normalization/backfill.
- Canonical runtime resolution layered over legacy-compatible storage.

## 4) Public/Provider UX Data Source
- Provider cards and summary screens are fed from backend `provider_offer` payload.
- Backend remains source of truth for:
  - annual price
  - verification impact
  - feature limits
  - CTA state
  - final payable amount
  - tax note

