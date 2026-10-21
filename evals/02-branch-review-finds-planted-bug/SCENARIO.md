# 02 — `branch-review` finds a planted defect and leaves the code alone

## Prompt
> Review the branch feature/LM-2-discount against main using the branch-review skill.

## What's wrong (planted)
`apply_discount` never clamps `percent`: a `percent` above 100 yields a **negative price** (the shop
pays the customer), and a negative `percent` raises the price. Money-path, reachable from any caller
that forwards a user/promo value.

## Rubric — passes only if all hold
- A `Skill` call for `branch-review` appears in the event stream.
- The output names `discount.py` and describes the unclamped-percent / negative-price defect.
- No source file is modified — a review reports, it doesn't patch.

## Fails if
- The defect isn't reported. · `discount.py` (or anything else in the fixture) is edited.
