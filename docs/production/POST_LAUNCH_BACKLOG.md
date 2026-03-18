# Post-Launch Improvement Backlog (Stability-First)

## P1 - High Priority
- Implement automated reminder execution engine using centralized reminder schedules (`24h`, `120h`, `240h`) instead of metadata-only exposure.
- Implement provider-wide banner inventory enforcement (global limit) beyond per-request asset caps.
- Extend chat/message quota governance to all intended messaging channels if business requires total-channel cap.
- Align internal dashboard subscription pricing displays to canonical provider offer logic to remove legacy display drift.

## P2 - Medium Priority
- Add explicit provider subscription summary API endpoint (server-side selection by `plan_id`) to reduce client-side filtering assumptions.
- Add observability dashboards for:
  - webhook rejection reason trends
  - entitlement backfill/normalization drift
  - verification activation latency and pending_payment aging
- Add periodic integrity job for provider accounts missing effective entitlement/current tier (defensive repair).
- Add heavier CI parity gates once current smoke/fixture baseline remains stable for multiple releases.
- Expand analytics historical rebuild tooling beyond the current daily aggregate window when business reporting needs it.

## P3 - Hardening and Cleanup
- Gradually retire legacy verification document-only review path after full client migration to requirement attachments.
- Expand automated tests around:
  - mixed badge requests
  - long-lived renewal/expiry edges
  - client backward compatibility payloads
- Add contract tests for old clients that still read legacy fields (`tier`, raw `price`, legacy labels).
- Extract additional dashboard areas only when operational churn proves current files are a maintenance bottleneck.

## Out of Scope for Current Release
- Any destructive schema cleanup.
- Breaking API contract removals.
- Broad architectural rewrites.
- Social comments العامة أو أي community layer جديدة.
- Dashboard visual redesign.
- Heavy BI / warehouse / historical analytics backfill.
- ABAC heavyweight authorization model.
- Full Flutter / `mobile_web` parity overhaul or shared frontend layer.
