# Domain checklist packs

Reusable, sourced check sets for recurring problem domains. The generic negative set in the main checklist catches input-boundary bugs; these packs catch the **domain-specific traps** that a generic pass misses (a payment double-charge on webhook retry, a session not regenerated on login, a file-upload magic-byte bypass).

## How `test-iteration` uses them

1. **Detect the domain(s) in triage (step 5)** — from the diff, decide which domains the change actually touches (a payment endpoint → `payments`; a login/session/token change → `auth-sessions`; a `<form>` / validation change → `forms`; an upload handler → `file-upload`; a search/query feature → `search`; a translated/localized surface → `i18n-l10n`).
2. **Fold the matching pack into the tailored checklist (step 6)** — don't paste it whole and don't run it blindly: pick the items the change can actually break, drop the rest with the usual `N/A — <reason>`, and add feature-specifics on top.
3. **Each pulled item still gets** Risk (H/M/L), Trace (→ AC / ticket), and an Evidence type when run (a `runtime`/security item needs `observed-data`/`api`/`log`, per the evidence-gate).

These packs supplement — they never replace — the AC-derived and code-derived checks. An AC with no pack behind it is still tested; a pack item with no relevance to this change is dropped, not forced.

## Packs

| Pack | Pull when the diff touches… |
|------|------------------------------|
| [payments](payments.md) | charge/capture/refund/payout, payment state machine, gateway webhooks |
| [auth-sessions](auth-sessions.md) | login, logout, session/cookie/token handling, password reset, MFA |
| [forms](forms.md) | a `<form>`, field validation (client or server), submission flow |
| [file-upload](file-upload.md) | any user file upload / import handler |
| [search](search.md) | a search box, query endpoint, relevance/filter/pagination |
| [i18n-l10n](i18n-l10n.md) | translated strings, locale formatting, RTL, encoding |

> Packs are starting points grounded in current references (OWASP ASVS/WSTG/Cheat Sheets, Microsoft Globalization, fintech payment-testing guides), cited at the foot of each file. Treat them as a floor, not a ceiling.
