# Source snapshot publication

Publication date: **23 October 2026** (Asia/Kolkata).

This is a snapshot of the existing ShreyX Tube working project, version **1.5.0+14**, including previously uncommitted improvements. It does not claim the application was first developed today.

- Original repository: https://github.com/ShreyashPatil123/shreyx-tube.git
- Its Git directory, remote, commits and working files were not imported, rewritten, reset or replaced.
- The new repository has its own Git directory and one initial snapshot commit, created using the actual system clock. No author/committer date override is used.
- Earlier development history remains in the original repository; this new history records publication only.
- Application/native/gateway/test code was copied byte-for-byte. Documentation and ignore rules were adapted for publication; internal device/task reports were excluded.
- APKs, keystores, environment files, account sessions, runtime databases and caches are excluded.
- The owner uses a GitHub noreply commit identity rather than a personal email address.

## Validation

Before the publication commit, this clean copy passed:

- Locked dependency resolution, without changing the source lockfile.
- Flutter static analysis with no issues and all 293 Flutter tests.
- All 16 gateway tests (provider mocked; no live Gemini claim).
- Review of all 158 staged files: no forbidden cache/build/environment/credential paths or high-signal privileged credential patterns. Four deliberately invalid user-info URLs in rejection tests were reviewed as synthetic fixtures.

Application source was preserved, including inherited whitespace; no unrelated formatting cleanup was performed. The security review is a scoped pattern/manual check, not an exhaustive professional audit. Repository, remote commit/tree and original-repository preservation are checked after pushing and recorded in the completion report.
