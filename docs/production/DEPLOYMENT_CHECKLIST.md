# Deployment Checklist (Production Stability)

## A) Pre-Deploy
- Confirm environment variables are set:
  - `SECRET_KEY`
  - `BILLING_WEBHOOK_SECRETS` (or provider-specific secret vars)
  - DB/cache/Celery settings per environment
- Ensure payment provider webhook route is reachable:
  - `/api/billing/webhooks/<provider>/`
- Freeze release commit and tag.
- Review migration plan and expected command order.

## B) Deploy Order
1. Deploy application code.
2. Run DB migrations:
   - `cd backend`
   - `.\\.venv\\Scripts\\python.exe manage.py migrate`
3. Seed canonical plans:
   - `.\\.venv\\Scripts\\python.exe manage.py seed_plans`
4. Dry-run data maintenance:
   - `.\\.venv\\Scripts\\python.exe manage.py backfill_provider_basic_entitlements --dry-run`
   - `.\\.venv\\Scripts\\python.exe manage.py normalize_current_subscriptions --dry-run`
5. Execute maintenance:
   - `.\\.venv\\Scripts\\python.exe manage.py backfill_provider_basic_entitlements`
   - `.\\.venv\\Scripts\\python.exe manage.py normalize_current_subscriptions`
6. Restart API and worker processes.
7. Ensure Celery beat includes:
   - `verification.expire_badges_and_sync`

## C) Post-Deploy Smoke Checks
- `manage.py check` passes.
- Provider can view `/plans/` and `/plans/summary/`.
- Plans API returns `provider_offer`.
- Subscription checkout creates invoice with canonical annual amount.
- Verification pricing endpoint returns 100/50/0 by tier.
- Webhook success activates paid flow only when signature and amount are valid.
- Webhook reversal revokes paid activation effects.
- Competitive request gating and promo/message limits behave per tier.

## D) Release Acceptance Criteria
- No 5xx spike on subscription/verification/billing endpoints.
- No blocked provider onboarding due to entitlement logic.
- No mismatch between summary shown amount and invoice payable amount.
- No unauthorized access into provider-only endpoints.

