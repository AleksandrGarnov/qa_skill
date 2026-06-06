# Pack — Forms

Pull when the change touches a `<form>`, field validation, or a submission flow. Test **all four layers**: field-level, cross-field, client-side, server-side — and remember client-side validation can always be bypassed.

## Validation
- [ ] Required field rejects empty/whitespace-only submission with a clear message
- [ ] **Server-side validation holds when client-side is bypassed** (submit via direct API / devtools) — the load-bearing check
- [ ] BVA on length/numeric limits: 0 / 1 / max / max+1 → boundaries behave (e.g. 150-char field rejects 151)
- [ ] Format masks (email, phone, card) accept valid variants (spaces/dashes) and reject invalid
- [ ] Special characters & long strings → escaped, stored intact, no 500
- [ ] Cross-field / conditional rules (field B required only if A set) enforced both sides

## Submission flow (the submit is the start, not the end)
- [ ] Full chain on success: client passes → payload reaches server → server validates → **DB record correct** → confirmation shown → downstream effects fire (email, webhook, workflow)
- [ ] Double / rapid re-submit → no duplicate record (idempotency)
- [ ] Partial submit / navigate away mid-form → no corrupt half-record; draft behaviour as specified
- [ ] Network failure mid-submit → clear state, no data loss, retry safe

## Input UX & accessibility
- [ ] Paste and password-manager autofill work; **paste is never blocked** in password fields
- [ ] Autocomplete attributes set for personal-data fields (`name`/`email`/`tel`/`street-address`)
- [ ] Errors identify the field and how to fix it (not "Invalid input"); associated via `aria-describedby` + `aria-invalid`; an error summary (`role="alert"`) appears on submit and takes focus
- [ ] Inline validation fires on blur/submit, not on every keystroke (no premature errors)

> Sources: OWASP-aligned form-testing guides (Virtuoso, QED42, FormCare), A11yPath forms accessibility checklist (WCAG 3.3.1/3.3.3/3.3.8).
