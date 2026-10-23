# Optional Gemini gateway

The Android app works without this service: pasted transcripts and the original labelled demo use an on-device extractive summary and evidence search. Generative summaries and answers require a separately operated HTTPS gateway, explicit consent in **You → Video intelligence → AI privacy**, and a per-user gateway access token. No provider key belongs in the Android app.

## Run and verify

Requires Node.js 22 or later; no npm dependencies or install step.

```sh
node --test server.test.mjs
node --env-file=.env server.mjs
```

Create a local `.env` only if needed; no environment file is published. Configure `GEMINI_API_KEY`, `AI_ACCESS_TOKENS` and optionally `GEMINI_MODEL` (default `gemini-2.5-flash`), `AI_DAILY_LIMIT` (100), `AI_USER_DAILY_LIMIT` (25), `AI_PER_MINUTE` (5), `HOST` (`127.0.0.1`) and `PORT` (8787). Keep it untracked and out of images and backups. Supply `GEMINI_API_KEY` through the hosting secret manager in production. Generate a different random gateway token for each user (for example, `node -e "console.log(require('node:crypto').randomBytes(32).toString('base64url'))"`) and put the comma-separated tokens in `AI_ACCESS_TOKENS`. Deliver each token privately to its user. These grant gateway access; they are not Google API keys. Rotate by replacing the environment value and restarting. Revoked tokens cannot authenticate after restart.

`GET /health` checks that the process responds; `GET /ready` is **503** until both provider key and access tokens exist. Readiness cannot prove provider permissions, model availability or quota. Verify an authenticated request using a short non-sensitive transcript before sharing a deployment. Do not include tokens in URLs, public commands, screenshots, APK assets or repository files.

Development binds to `127.0.0.1:8787`. Debug APKs allow explicit HTTP loopback for `adb reverse tcp:8787 tcp:8787`; release APKs require a public HTTPS origin. In AI privacy enter that origin and your **gateway** token, enable external processing and save. In the workbench separately choose external AI and run the analysis. Changing privacy settings cancels in-flight work. There is no silent remote fallback.

## Hosting boundary

`docker build -t shreyx-intelligence server` builds the included nonroot container. A deployment needs a host capable of running Node/containers, managed TLS, environment secrets and ingress protection. Static hosting alone cannot run it. A small existing Node/container host is compatible. Google Cloud Run or Firebase App Hosting would require a configured project, eligibility and potentially a billing account; neither is activated by this project. **No cloud service or billing was enabled, and no public backend was deployed.**

For a limited demonstration use **one replica**, TLS termination and restricted audience. Set edge connection/request limits; the server caps connections at 32 and concurrent provider calls at two. Do not publish a shared gateway token. For a public or multi-instance product, first add real user enrollment, a shared persistent rate-limit/usage store, abuse monitoring with content/credential redaction and administrator-controlled quotas. The current memory-only counters reset when the process restarts and do not coordinate across replicas. They are request budgets, not provider billing caps. A leaked token can spend its request allowance; revocation and provider quotas remain necessary.

## Request and data policy

Only authenticated native `POST /v1/analyze` requests are accepted. Browser-origin calls are rejected. Accepted input: a valid video ID, title, task (`summary` or `ask`), current question and 1–400 transcript sections with IDs and optional actual cue times. The service never fetches a video URL, follows a user-supplied destination, receives YouTube sessions or executes tools. Outbound requests go only to the fixed Google Gemini API origin. User content is placed in the user message; system instructions and the schema are fixed. Unknown input fields are discarded.

Limits: 256 KB request, 50,000 transcript characters, 1,000 question characters, 96 KB provider response, 3,072 output tokens, 25-second upload/provider deadline. Defaults: 5 requests/minute and 25/day per gateway token, 100/day total (UTC). At most 32 configured user tokens. Requests that reach the provider consume allowance even if the provider fails. No automatic retry. Use smaller excerpts when output is truncated; rate-limit errors offer local analysis instead.

Structured responses must contain valid segment references and exact matching source excerpts. Timestamp values come from the transcript, never the model. Unsupported answers are replaced with a fixed explanation. Exact quotations do **not** prove that every generated sentence follows from them; users must verify summaries against the excerpts. Prompt injection and model error cannot be ruled out by schema validation.

The server retains no transcript/response history and logs neither content nor credentials. Requests remain in process memory during execution. The hosting provider, TLS proxy and Google still process traffic; configure their logging and retention separately. The app stores notes/responses in its private SQLite database **only on explicit Save** (up to 50 videos), and its gateway access token in Android secure storage. Database content is not separately encrypted by this feature; device compromise can expose it. Existing Android backup exclusions apply. Unsaved transcripts/conversations and the bounded analysis cache stay in memory. Clear materials and full local reset cancel pending analysis and remove saved AI data; Incognito hides saved materials and disables saving/external processing.

## Google availability, terms and costs

Checked against official documentation on **23 October 2026**. `gemini-2.5-flash` remains listed in pricing; `GEMINI_MODEL` can select another compatible text model without changing client code. A model can later be retired or unavailable for a project/region. The gateway surfaces unavailability instead of assuming access. The standard `generateContent` configuration supports JSON MIME type and response schema; this is not the Live API.

- [Model pricing](https://ai.google.dev/gemini-api/docs/pricing): free access is model/feature dependent; paid usage and hosting may cost money. No unlimited free allowance is promised.
- [Rate limits](https://ai.google.dev/gemini-api/docs/rate-limits): quotas vary by model/tier and apply per project, not per API key. Check the actual project in AI Studio. This service's smaller budgets do not create provider quota.
- [Gemini additional terms](https://ai.google.dev/gemini-api/terms): unpaid input/output can be used to improve Google products, and human reviewers may process it. Do not send personal, sensitive or confidential material. Paid-service and regional terms differ; EEA/Switzerland/UK clients have additional paid-service requirements. Confirm eligibility before deployment.
- [Standard generation configuration](https://ai.google.dev/api/generate-content#v1beta.GenerationConfig).

No API key/quota was available during implementation. Provider tests use deterministic mocks; **live Gemini accuracy, availability and costs are unverified**. Google Antigravity, Firebase and Google Cloud deployment tooling were not configured, so none was used or claimed.
