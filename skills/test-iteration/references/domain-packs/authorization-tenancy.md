# Pack — Authorization, RBAC & Multi-tenancy

Pull when the change touches **who is allowed to see or do what**: an endpoint that reads/writes a record by id, a role/permission check, an admin action, a tenant/organization/account boundary, a share/invite flow, an export/list/aggregation, or object ownership. This is OWASP **A01 Broken Access Control** — the most common serious web flaw — and it is `runtime` and security-critical: verify on **observed cross-account state** (what account A actually sees vs account B), never on a mocked `can()`/`authorize()` returning true.

**Test method (the whole pack leans on this).** Authorization bugs hide between accounts, so test with **two freshly-created subjects that must not see each other**: user A and user B in different roles and/or different tenants, plus one admin. For each check, perform the action as the *wrong* actor and **read out what is actually returned/changed** — the pass is "B's request for A's object returns 403/404 and B's data is unchanged", quoted from the real response, not "the guard looks correct". Attack first: try to reach A's data as B, escalate B to admin, cross the tenant line — then confirm the deny.

## Object-level access (IDOR / BOLA — horizontal)
- [ ] As user B, request **A's object by id** on every read route (`GET /orders/{A_id}`, `/invoices/{A_id}`, `/users/{A_id}`, download links, nested `/{A_id}/items`) → 403/404, **no** A data in the body (observe: B's request, A's id, raw response)
- [ ] As B, **mutate** A's object (`PUT/PATCH/DELETE /orders/{A_id}`, state transitions, comments) → denied **and** A's record verifiably unchanged afterward (read it back as A)
- [ ] Guessable/sequential/enumerable ids: incrementing or decrementing an id does not walk into another owner's records; UUIDs aren't leaked in list/search responses of a different tenant
- [ ] Ownership is checked on the **object**, not just that *some* record with that id exists — a valid id owned by A is rejected for B (not silently served)
- [ ] Second-order / nested references: a child resource id (`/orders/{B_own}/items/{A_item}`) can't smuggle in another owner's child by pairing a legit parent with a foreign child id

## Function-level access (privilege escalation — vertical)
- [ ] As a normal user, call **admin/privileged endpoints directly** (URL/method/verb known from the diff, not just hidden in the UI) → denied; hiding the button is not the control
- [ ] Deny-by-default: a **new or unlisted** route/action requires an explicit permission — an endpoint with no check returns 403, not 200 (probe a route the diff added)
- [ ] Role tampering via **mass assignment**: B can't set `role`, `is_admin`, `tenant_id`, `owner_id`, `permissions`, `account_id` through a create/update body or a hidden form field (submit the extra field; read back the stored role)
- [ ] Forced browsing to a higher-privilege step: skipping an approval/verification step by calling the final endpoint directly is rejected
- [ ] HTTP method/verb confusion (`GET` vs `POST` vs `PUT`), trailing-slash, case, or path-normalization variants don't bypass the middleware that guards the canonical route

## Tenant / account isolation (multi-tenancy)
- [ ] **Cross-tenant read is impossible on every query path**: as tenant-B, list/search/filter/export/report → results contain **only** B's rows; A's data never appears (observe: the full B result set and the full A result set side by side — the CLAUDE.md "show what A sees and what B sees" method)
- [ ] Every query in the changed code is **scoped by tenant/owner at the data layer** (a `WHERE tenant_id = ?` or equivalent), not filtered only in the UI/serializer — an aggregate/`COUNT`/`SUM`/analytics endpoint doesn't sum across tenants
- [ ] A record **created** by the action is stamped with the actor's tenant/owner and can't be created into another tenant by supplying a foreign `tenant_id`
- [ ] Shared/global resources (templates, tags, lookups) are read-only across tenants; a tenant can't edit or delete another tenant's or the global set
- [ ] Cache keys, rate-limit buckets, file paths, and generated URLs are **tenant-scoped** — no cross-tenant cache bleed or predictable path that serves another tenant's file
- [ ] Invite/join/switch-tenant flows: a user removed from tenant A immediately loses access (existing sessions/tokens re-checked); switching tenants doesn't retain the previous tenant's scope

## Indirect leaks & oracles
- [ ] **List/search/export don't leak** what direct-read forbids: a foreign object excluded from `GET /{id}` must also be absent from search hits, autocomplete, `/export`, notifications, and webhook payloads
- [ ] Error/response **oracle**: a forbidden-but-existing object and a truly-missing object return the **same** status + body + timing (a `403` for existing vs `404` for missing lets B enumerate A's ids)
- [ ] Verbose errors/stack traces don't disclose another owner's field values, ids, or existence
- [ ] Aggregations, counts, and "N others" hints don't reveal the presence or volume of another tenant's data

## Token / session scope
- [ ] An API token/JWT carries and **enforces** its scope and tenant claim — a token minted for tenant A can't act on tenant B by changing a path id; scope down (read-only token can't write)
- [ ] Permission/role changes take effect on the **next request** (stale cached claims can't retain a revoked admin right); a downgraded user can't keep acting on a long-lived token

> Sources: OWASP Top 10 **A01:2021 Broken Access Control**; OWASP **API Security Top 10** (API1 BOLA, API3 Broken Object Property Level Authorization / mass assignment, API5 Broken Function Level Authorization); OWASP ASVS V4 (Access Control); OWASP WSTG-ATHZ (Authorization Testing — IDOR, privilege escalation); OWASP Authorization & Mass Assignment Cheat Sheets.
