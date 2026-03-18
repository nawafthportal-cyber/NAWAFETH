## Summary

- What changed:
- Why:

## Risk

- [ ] Low
- [ ] Medium
- [ ] High

## Rollout

- [ ] No flag needed
- [ ] Existing flag updated
- [ ] New flag added
- [ ] Rollout notes updated in `docs/production/SPRINT4_RELEASE_FLAGS.md` if behavior changed

## Parity checklist

- [ ] This PR does not affect shared API/UI contracts
- [ ] I reviewed affected contracts in `docs/contracts/sprint2`, `docs/contracts/sprint3`, and `docs/contracts/sprint4`
- [ ] I updated fixtures/checklists if payloads or statuses changed
- [ ] I validated critical path impact on Flutter and `mobile_web` where applicable

## Tests

- [ ] Relevant backend tests
- [ ] Dashboard/regression tests if internal ops changed
- [ ] Flutter/mobile_web smoke or fixture checks if parity-impacting
- [ ] Backend critical workflow coverage remains valid for touched release-critical paths

## Release-critical impact

- [ ] This PR does not change moderation / RBAC / analytics rollout assumptions
- [ ] If it does, I updated `docs/production/SPRINT4_ACCEPTANCE_PACK.md` or release docs accordingly
