# Pack — Auth & Sessions

Pull when the change touches login, logout, session/cookie/token handling, password reset, or MFA. These are security-critical and `runtime` → verify on **observed** session/cookie/token state, not on a mocked `isAuthenticated()`.

## Session lifecycle (fixation / hijacking)
- [ ] A **new** session ID with high entropy is issued **on successful login**; the pre-login ID is invalidated → defends session fixation (observe: cookie value changes after login)
- [ ] Session invalidated on logout, on idle timeout, **and** on absolute timeout
- [ ] Session ID never appears in the URL; cookie flags `HttpOnly` + `Secure` + `SameSite` set
- [ ] On password change/reset, all **other** active sessions are terminated (across SSO/relying parties if any)

## Credential flows
- [ ] Brute-force / automated attempts are throttled or locked out (lockout mechanism present and effective)
- [ ] Account enumeration closed: login, registration, and password-reset return the **same message/timing** for valid vs invalid accounts
- [ ] "Half-open" attack: a password-reset/forgot flow does **not** populate a usable authenticated session before identity is fully verified (can't change password/email/MFA mid-flow)
- [ ] Password reset token: single-use, expires, bound to the user, invalidated after use

## Tokens (JWT / OAuth / API keys)
- [ ] Stateless tokens are signed (and encrypted where needed); tampered/`alg:none`/replayed/expired tokens are rejected
- [ ] Refresh-token rotation: an old refresh token can't be reused after rotation
- [ ] OAuth tokens for linked apps are revocable; static API secrets aren't used as session tokens

## MFA & sensitive actions
- [ ] MFA enrolment/login can't be bypassed; re-auth required for sensitive changes (email, password, MFA device)

> Sources: OWASP ASVS V3 (Session Management), OWASP Top 10 A07:2021, OWASP Session Management Cheat Sheet, OWASP WSTG (Session Fixation).
