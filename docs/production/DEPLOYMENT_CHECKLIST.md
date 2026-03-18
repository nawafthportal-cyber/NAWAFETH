# Deployment Checklist (Production Stability)

## A) Pre-Deploy
- Confirm environment variables are set:
  - `SECRET_KEY`
  - `BILLING_WEBHOOK_SECRETS` (or provider-specific secret vars)
  - DB/cache/Celery settings per environment
- Review Sprint 4 flags matrix:
  - `FEATURE_MODERATION_CENTER`
  - `FEATURE_MODERATION_DUAL_WRITE`
  - `FEATURE_RBAC_ENFORCE`
  - `RBAC_AUDIT_ONLY`
  - `FEATURE_ANALYTICS_EVENTS`
  - `FEATURE_ANALYTICS_KPI_SURFACES`
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
   - `analytics.rebuild_daily_stats`

## B.1) Sprint 4 staged enablement
1. Keep all new flags disabled on first deploy.
2. Enable `FEATURE_ANALYTICS_EVENTS=1`.
3. Enable `FEATURE_MODERATION_CENTER=1` after verifying dashboard access and API routes.
4. Keep `RBAC_AUDIT_ONLY=1` and `FEATURE_RBAC_ENFORCE=0` for first production rollout.
5. Execute one daily analytics rebuild cycle before enabling KPI surfaces.
6. Enable `FEATURE_ANALYTICS_KPI_SURFACES=1`.
7. Enable `FEATURE_MODERATION_DUAL_WRITE=1` only after complaint/report smoke checks pass.
8. Enable `FEATURE_RBAC_ENFORCE=1` only after reviewing audit-only denies and false positives.

## C) Post-Deploy Smoke Checks
- `manage.py check` passes.
- Provider can view `/plans/` and `/plans/summary/`.
- Plans API returns `provider_offer`.
- Subscription checkout creates invoice with canonical annual amount.
- Verification pricing endpoint returns 100/50/0 by tier.
- Webhook success activates paid flow only when signature and amount are valid.
- Webhook reversal revokes paid activation effects.
- Competitive request gating and promo/message limits behave per tier.
- Messaging report flow still creates support ticket successfully.
- Complaint ticket flow still works and, when enabled, dual-writes to moderation.
- Moderation queue/detail/actions work for authorized operators.
- Notifications unread count and combined unread badges remain mode-aware.
- Analytics KPI endpoints return aggregate-backed data only after enablement.

## D) Release Acceptance Criteria
- No 5xx spike on subscription/verification/billing endpoints.
- No blocked provider onboarding due to entitlement logic.
- No mismatch between summary shown amount and invoice payable amount.
- No unauthorized access into provider-only endpoints.
- No false-deny spike on moderation / support / promo / verification / extras / subscriptions operator actions.
- No divergence in unread / notifications / provider profile critical parity responses.
