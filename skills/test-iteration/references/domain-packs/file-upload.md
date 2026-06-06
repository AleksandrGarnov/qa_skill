# Pack — File upload

Pull when the change touches any user file upload / import handler. Unrestricted upload → RCE / XSS / SSRF / DoS / path traversal. Weak controls over **extension, MIME, content/magic-bytes, size, filename, storage location** are the attack surface. All security `runtime` → confirm on **observed** server behaviour (is it stored? does it execute?).

## Type validation (don't trust the client)
- [ ] Extension allowlist (not denylist); reject `.php`/`.phtml`/`.phar`/`.svg`/`.html`/`.htaccess`/`web.config` where not needed
- [ ] Double extension `shell.php.jpg` and case variants `.pHp` → rejected
- [ ] Null-byte `shell.php%00.jpg` → not truncated to `.php`
- [ ] `Content-Type` header spoof (`image/jpeg` on a script) → not accepted on header alone
- [ ] Magic-byte check present **and** can't be bypassed by prepending `FF D8 FF` to a script / EXIF-embedded payload

## Size & resource (DoS)
- [ ] Size limit enforced; oversized upload rejected (observe: storage not filled)
- [ ] Compressed files checked against **uncompressed** size and file count before extraction (zip-bomb / Zip-Slip)

## Filename & storage
- [ ] User filename not used directly on the filesystem → stored under a generated UUID; path traversal (`../`, RTLO `file‮gpj.php`) neutralised
- [ ] Uploaded file in the upload dir **does not execute** (request it back → served, not run)
- [ ] Served with `Content-Disposition: attachment` + safe `Content-Type` (guards Reflective File Download / stored XSS)
- [ ] Filename in JSON/URL params validated → no RFI/SSRF via filename

> Sources: OWASP File Upload Cheat Sheet, OWASP ASVS V12 (Files & Resources), OWASP-based upload checklists (EmadYaY, OSINT Team).
