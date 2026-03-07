# Subscription + Verification System Documentation

## 1) Subscription Domain

### Canonical Tiers
- `basic` (الأساسية)
- `pioneer` (الريادية)
- `professional` (الاحترافية)

Alias compatibility is maintained for legacy values (`riyadi`, `pro`, `leading`, `pioneer`, `professional`, etc.) through canonical tier helpers.

### Entitlement Rules
- Basic is free default provider entitlement.
- Basic is assigned on provider transition and can be backfilled safely.
- Paid upgrades remain separate historical records.
- Only one effective current tier is resolved at runtime.

### Provider Offer Payload
Plans API provides `provider_offer` as source of truth for:
- Arabic plan name
- annual price
- verification impact
- capability rows for cards/summary
- CTA state (`الباقة الحالية`, `ترقية`, etc.)
- final payable amount and tax note

## 2) Verification Domain

### Workflow
1. request created
2. evidence uploaded
3. admin review
4. approve/reject
5. payment if required
6. activation

### Evidence Authority
- Requirement attachments are authoritative.
- Legacy document uploads are mirrored into requirement attachments for compatibility.

### Pricing
- Basic: `100 SAR` per verification/year (blue and green)
- Pioneer: `50 SAR` per verification/year (blue and green)
- Professional: `0 SAR` (included)

Charging model:
- once per approved verification badge flow
- not once per approved requirement

Tax policy:
- verification pricing is treated as final inclusive amount for this flow
- invoice payable equals displayed price

## 3) Badge Safety
- Badge activates only after approved/evidenced and paid/free-completed verification truth.
- Badge visibility is revoked when payment is reversed/refunded/cancelled or verification expires.
- Provider profile flags are synchronized from verified badge truth.

## 4) Security and Access
- Only providers may subscribe or request verification.
- Trusted payment confirmation is mandatory for paid activations.
- Webhook processing validates signature, amount, currency, and event idempotency.

## 5) Maintenance Commands
- `python manage.py seed_plans`
- `python manage.py backfill_provider_basic_entitlements --dry-run`
- `python manage.py backfill_provider_basic_entitlements`
- `python manage.py normalize_current_subscriptions --dry-run`
- `python manage.py normalize_current_subscriptions`

