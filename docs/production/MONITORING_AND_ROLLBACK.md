# Monitoring and Rollback Notes

## 1) Monitoring Priorities

### Billing Integrity
- Track webhook rejection reasons:
  - `invalid_signature`
  - `duplicate_event`
  - `amount_mismatch`
  - `currency_mismatch`
- Alert on sudden increases in rejected webhook events.
- Track activation attempts where `invoice.status=paid` but `payment_confirmed=false`.

### Subscription Health
- Monitor providers with no effective current tier (should be near zero after backfill).
- Monitor overlap normalization counts from periodic maintenance runs.
- Monitor checkout failures by error code:
  - current plan selected
  - downgrade attempt
  - missing provider eligibility

### Verification + Badge Safety
- Monitor verification requests stuck in `pending_payment` too long.
- Monitor activation failures due to missing evidence/approval/payment.
- Monitor badge revocations caused by reversal/refund/cancel/expiry.

### Feature Gating
- Track denial counters for:
  - competitive request early access
  - direct chat quota
  - promotional control violations
  - banner limit violations

### Moderation + RBAC
- Monitor dual-write consistency between complaint/report sources and `ModerationCase`.
- Track `RBAC_POLICY_DENIED` vs `RBAC_POLICY_AUDIT_ONLY` volume after each rollout step.
- Alert on sudden growth in overdue moderation cases or escalation spikes.

### Analytics
- Monitor daily aggregate rebuild success/failure and row counts.
- Monitor sudden zero-value KPI surfaces after enabling `FEATURE_ANALYTICS_KPI_SURFACES`.
- Track event ingestion failures or unexpected growth in duplicate dedupe keys.

## 2) Recommended Alerts
- High: webhook invalid signature spike
- High: unexpected drop in successful paid activations
- High: elevated 4xx/5xx on `/api/subscriptions/*`, `/api/verification/*`, `/api/billing/*`
- High: elevated 403 spike on operator actions immediately after RBAC enforcement enablement
- High: analytics rebuild task failures or moderation dual-write exceptions
- Medium: large increase in `normalize_current_subscriptions` corrected rows
- Medium: moderation backlog overdue growth

## 3) Rollback Strategy

### Code Rollback
- Roll back to previous known-good tag first.
- Keep DB schema additive changes in place (no destructive rollback required).

### Operational Rollback
- If webhook pipeline degrades:
  - pause provider webhook integration
  - continue with controlled mock/manual trusted test flows for validation only
  - keep untrusted activations blocked
- If moderation consistency degrades:
  - disable `FEATURE_MODERATION_DUAL_WRITE`
  - keep complaint/report source flows active
- If operator denials are incorrect:
  - disable `FEATURE_RBAC_ENFORCE`
  - keep `RBAC_AUDIT_ONLY=1`
- If KPI surfaces look incomplete:
  - disable `FEATURE_ANALYTICS_KPI_SURFACES`
  - keep `FEATURE_ANALYTICS_EVENTS=1`

### Data Stabilization After Rollback
- Re-run:
  - `backfill_provider_basic_entitlements --dry-run`
  - `normalize_current_subscriptions --dry-run`
- If output is safe, execute both commands to restore consistent entitlement/current-tier state.

## 4) Rollback Guardrails
- Never use destructive resets on production data.
- Do not manually force invoice paid/unpaid for trusted flows outside approved operational runbook.
- Preserve paid history rows and invoice trails.
- Do not switch on all Sprint 4 flags simultaneously on first rollout.
