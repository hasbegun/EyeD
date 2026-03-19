# EyeD Multi-Mode Architecture Plan

## Overview

Introduce three operational modes — **dev**, **prod**, **test** — governed by a single
environment variable `EYED_MODE`.  The mode propagates from a root `.env` file
through `docker-compose.yml` into every service (iris-engine2, libiris, client2,
gateway, storage) and controls logging, security, FHE behaviour, and UI features.

---

## 1  Mode Definitions

| Aspect | **dev** | **test** | **prod** |
|---|---|---|---|
| Log level (services) | `debug` | `info` | `warn` |
| Log level (libiris / spdlog) | `debug` | `info` | `warn` |
| FHE compiled in (libiris) | yes | yes | yes |
| FHE enabled at runtime | toggleable (default ON) | configurable (default ON) | **always ON, locked** |
| `EYED_ALLOW_PLAINTEXT` | `true` | `true` | **`false`** |
| FHE toggle API (`POST /config/fhe`) | **available** | available | **does not exist** |
| Config read API (`GET /config`) | full | full | **operational only** (no sensitive fields) |
| Template visualisation (gallery) | shown when plaintext | shown when plaintext | **never** (always encrypted) |
| client2 FHE toggle switch | **visible** | hidden | **hidden** |
| client2 mode badge | "DEV" ribbon | "TEST" ribbon | none |
| Docker build type (CMake) | `Release` | `Debug` + sanitizers | `Release` + LTO |
| Database name | `eyed_dev` | `eyed_test` | `eyed` |
| Ports exposed on host | all (9500-9510) | all | all (via `docker-compose.prod.yml`) |
| Health-check interval | 5 s | 5 s | 30 s |
| Secrets handling | plain-text files | plain-text files | plain-text files (strict perms) |
| Integration-test profile | opt-in | **auto-included** | excluded |
| FHE toggle persistence | yes (mounted volume) | yes (mounted volume) | N/A (always ON) |

---

## 2  Single Source of Truth

```
# .env  (project root — git-ignored, OPTIONAL)
EYED_MODE=dev
```

**If `.env` is absent, the default is `prod`.**  This is the safe-by-default
principle: a fresh clone or a deployment without an explicit `.env` file
automatically runs in the most secure mode.  Developers must explicitly
create `.env` with `EYED_MODE=dev` to unlock dev features.

`docker-compose.yml` reads `${EYED_MODE:-prod}` and injects it into every
container as an environment variable.  Each component then adapts its behaviour
at **runtime** (services) or **build time** (client2 Flutter, libiris CMake
optimisation level).

### Propagation Path

```
.env  ──►  docker-compose.yml
              │
              ├─► iris-engine2  (EYED_MODE env var)
              │       └─► Config::from_env()  reads EYED_MODE
              │       └─► CMake build arg EYED_MODE → libiris spdlog default
              │
              ├─► client2  (--dart-define=EYED_MODE=$EYED_MODE at build time)
              │       └─► Dart const String.fromEnvironment('EYED_MODE')
              │
              ├─► gateway  (EYED_MODE → log level mapping)
              ├─► storage  (EYED_MODE → log level mapping)
              └─► key-service (EYED_MODE → log level mapping)
```

---

## 3  Detailed Design Per Component

### 3.1  iris-engine2 (`src/config.h`)

Add `EYED_MODE` to the `Config` struct.

```cpp
// New field
std::string mode = "prod";  // "dev" | "test" | "prod"  (safe default)

// In from_env():
if (auto* v = std::getenv("EYED_MODE")) c.mode = v;

// Derive defaults from mode when explicit env vars are absent:
//   prod → fhe_enabled=true, allow_plaintext=false, log_level=warn
//   test → fhe_enabled=true, allow_plaintext=true,  log_level=info
//   dev  → fhe_enabled=true, allow_plaintext=true,  log_level=debug
// If EYED_MODE is unset, defaults to "prod" (safe-by-default).
```

Explicit env vars (e.g. `EYED_FHE_ENABLED=false`) always override mode defaults,
so existing deployments keep working unchanged.

### 3.2  iris-engine2 — New Endpoints

#### `GET /config`  (all modes)

Returns current runtime configuration.

**dev / test response** — full visibility:

```json
{
  "mode":            "dev",
  "fhe_enabled":     true,
  "fhe_active":      true,
  "allow_plaintext": true,
  "log_level":       "debug",
  "gallery_size":    42,
  "db_connected":    true,
  "db_name":         "eyed_dev",
  "he_key_dir":      "/keys"
}
```

**prod response** — sensitive and inferrable fields are **omitted entirely**
(not redacted, not masked — simply absent from the JSON).  `mode` is not
returned (if you can reach this endpoint without it, it's prod).  `fhe_active`
is not returned (in prod it is always true — confirming it adds no value and
only acknowledges the existence of the toggle concept to an attacker).

```json
{
  "gallery_size":    42,
  "db_connected":    true,
  "version":         "0.1.0"
}
```

Rationale: every field in a prod response must earn its place.  `mode` and
`fhe_active` are constants in prod — returning them leaks architectural
details without operational benefit.

#### `POST /config/fhe`  (dev & test only)

Toggle FHE at runtime.  Body: `{"enabled": false}`.

**In prod mode this endpoint does not get registered** — a 404 is returned.

When toggled OFF:
- New enrollments store plaintext templates.
- Gallery matching uses plaintext HD.
- `GET /gallery/template/:id` returns iris/mask code visualisations.

When toggled back ON:
- New enrollments encrypt templates.
- **Existing plaintext templates remain plaintext** (no retroactive encryption).
- Gallery matching uses the appropriate method per template.

### 3.3  iris-engine2 — FHE Toggle Runtime Safety

The `FHEManager` is already initialised at startup regardless of the toggle.
The toggle only changes `config.fhe_enabled`, which gates:
- `routes_enroll.cpp` — encrypt-before-persist vs plaintext persist
- `routes_gallery.cpp` — `is_encrypted` flag on template detail response
- `gallery.cpp` — match strategy selection

No restart is needed. The toggle is atomic (single bool, already read under mutex
or in request handlers sequentially via httplib's thread model).

### 3.4  libiris (`.libiris/`)

#### Compile-time

`IRIS_ENABLE_FHE=ON` in **all** modes (FHE code always compiled in).

The `EYED_MODE` Docker build arg controls CMake flags:

| Mode | `CMAKE_BUILD_TYPE` | Extra flags |
|---|---|---|
| dev | `Release` | `-march=native` |
| test | `Debug` | `-march=native -DIRIS_ENABLE_SANITIZERS=ON` |
| prod | `Release` | `-march=native -flto` |

#### Runtime (spdlog)

libiris uses `spdlog` for logging.  iris-engine2 sets the spdlog default level
at startup based on `config.mode`:

```cpp
// In main.cpp, after Config::from_env():
if (config.mode == "prod")      spdlog::set_level(spdlog::level::warn);
else if (config.mode == "test") spdlog::set_level(spdlog::level::info);
else                            spdlog::set_level(spdlog::level::debug);
```

This automatically applies to all spdlog loggers inside libiris without any
libiris code changes.  If libiris later creates named loggers, they inherit
the global default.

### 3.5  client2 (Flutter web)

#### Build-time mode injection

`Dockerfile` passes the mode:

```dockerfile
ARG EYED_MODE=prod
RUN flutter build web --release \
    --dart-define=API_MODE=proxy \
    --dart-define=EYED_MODE=${EYED_MODE}
```

`docker-compose.yml`:

```yaml
client2:
  build:
    context: ./client2
    args:
      EYED_MODE: ${EYED_MODE:-prod}
```

#### Mode provider (`lib/config/mode_config.dart`)

```dart
class ModeConfig {
  static const String mode = String.fromEnvironment('EYED_MODE', defaultValue: 'prod');
  static bool get isDev  => mode == 'dev';
  static bool get isProd => mode == 'prod';
  static bool get isTest => mode == 'test';
}
```

#### FHE toggle (dev mode only)

New Riverpod provider:

```dart
// lib/providers/fhe_provider.dart
final fheEnabledProvider = StateNotifierProvider<FheNotifier, bool>((ref) {
  return FheNotifier(ref);
});
```

The notifier:
1. On init — calls `GET /engine/config` to read current `fhe_enabled` state.
2. On toggle — calls `POST /engine/config/fhe` with `{"enabled": <value>}`.
3. Updates local state on success.
4. Triggers gallery refresh so template visualisations update.

#### UI changes

**AppBar (dev mode only):**
```
[DEV] ─────────────────── [FHE: ON 🔒] [한국어]
```

- A "DEV" badge is shown in the AppBar.
- An `FHE: ON/OFF` toggle chip is shown next to the language button.
- In prod/test mode, neither appears.

**Gallery template detail:**
- Already works: `routes_gallery.cpp` returns `iris_code_b64`/`mask_code_b64`
  only when `!is_encrypted`.
- `enroll_gallery_tab.dart` already shows/hides visualisation based on
  `isEncrypted`.
- **No client2 gallery code changes needed** — the server controls what's returned.

### 3.6  docker-compose.yml

Use `${EYED_MODE}` variable substitution with defaults:

```yaml
services:
  iris-engine2:
    build:
      args:
        EYED_MODE: ${EYED_MODE:-prod}
    environment:
      EYED_MODE: ${EYED_MODE:-prod}
      EYED_LOG_LEVEL: ${EYED_LOG_LEVEL:-}    # empty = derive from mode

  gateway:
    environment:
      EYED_MODE: ${EYED_MODE:-prod}

  client2:
    build:
      args:
        EYED_MODE: ${EYED_MODE:-prod}
```

### 3.7  Makefile

```makefile
up: up-prod    ## Default: start in prod mode

up-dev:       ## Start in dev mode (requires .env or explicit override)
	EYED_MODE=dev docker compose up

up-prod:      ## Start in prod mode (default — same as plain `docker compose up`)
	docker compose -f docker-compose.yml -f docker-compose.prod.yml up

up-test:      ## Start in test mode (auto-includes integration-test profile)
	EYED_MODE=test docker compose --profile test up
```

---

## 4  Action Order

> **Security notes** in each phase reference the numbered items in §6.
> Resolve each cited concern before moving to the next phase.

### Phase 1 — Infrastructure ✅ DONE
1. ✅ Create `.env.example` documenting all vars; `.env` is optional (absent = prod).
2. ✅ Create `.gitignore` (ignore `.env`, `secrets/`, `build/`, `*.pyc`, etc.).
3. ✅ Update `docker-compose.yml` to pass `${EYED_MODE:-prod}` to all services.
4. ✅ Create `docker-compose.prod.yml` (hardcodes `EYED_MODE=prod`, keeps ports).
5. ✅ Update `Makefile` with `up` (→ `up-prod`), `up-dev`, `up-prod`, `up-test`.

> 🔒 **Security gate — Phase 1**
> - **S5** (Secrets in Git): verify `git status` shows `secrets/` and `.env`
>   are untracked after step 2.
> - **S4** (Mode Spoofing): confirm `docker-compose.prod.yml` hardcodes
>   `EYED_MODE=prod` so `.env` tampering cannot override it (step 4).

### Phase 1b — Database Split ✅ DONE
6. ✅ Create `secrets/db_name_engine2_dev.txt` (`eyed_dev`) and `secrets/db_name_engine2_test.txt` (`eyed_test`); update `secrets/db_name_engine2.txt` to `eyed` (prod).
7. ✅ Update `config/init-engine2.sh` to create `eyed_dev` and `eyed_test` databases (`eyed` created by postgres init via `01-init.sql`).
8. ✅ Create `docker-compose.dev.yml` / `docker-compose.test.yml` overrides (redefine `db_name_engine2` secret per mode); `up-dev` and `up-test` Makefile targets use these overlays.

> 🔒 **Security gate — Phase 1b**
> - **S3** (Plaintext Templates in Dev Database): confirm that `psql` against
>   the prod database (`eyed`) contains no rows after a dev enrollment — the
>   data must land only in `eyed_dev`.

### Phase 2 — iris-engine2 + libiris ✅ DONE
9. ✅ Add `mode` field to `Config` struct (`"prod"` default); `db_name`, `fhe_state_path` fields; derive `allow_plaintext` from mode before env overrides.
10. ✅ Set spdlog global level in `main.cpp` based on mode (prod→warn, test→info, dev→debug).
11. ✅ Add `GET /config` endpoint (`routes_config.cpp`): dev/test returns full config; prod returns only `gallery_size`, `db_connected`, `version`.
12. ✅ Add `POST /config/fhe` endpoint registered only in dev/test (prod → route not registered → 404).
13. ✅ FHE toggle persistence: write to `fhe_state_path` on toggle; read on startup (dev/test only). `fhe-config` Docker named volume mounted at `/config`.
14. ✅ Update `routes_enroll.cpp`: use `ctx.config.fhe_enabled && ctx.fhe.is_active()` for encryption gate and `is_encrypted` response field.
15. ✅ Update `routes_gallery.cpp`: `is_encrypted = ctx.config.fhe_enabled && ctx.fhe.is_active()`.
16. ✅ Update iris-engine2 `Dockerfile`: `ARG EYED_MODE=prod`, mode-based `CMAKE_BUILD_TYPE` (test→Debug+ASan, others→Release); `/config` dir created for persistence.
17. ✅ Update iris-engine2 `CMakeLists.txt`: add `src/routes_config.cpp` to executable sources.

> 🔒 **Security gate — Phase 2**
> - **S1** (FHE Toggle in Production): confirm `POST /config/fhe` returns 404
>   when `mode == "prod"` — the route must not be registered at all, not just
>   rejected at runtime (step 12).
> - **S2** (Config Endpoint Leaks): confirm prod `GET /config` response JSON
>   contains exactly three keys (`gallery_size`, `db_connected`, `version`) —
>   no extras, no nulls, no redacted strings (step 11).
> - **S6** (Log Verbosity): start in prod mode and confirm no identity names
>   or template metadata appear in logs at `warn` level (step 10).
> - **S8** (Mixed-Mode Templates): toggle FHE mid-session in dev, enroll both
>   ways, verify gallery matching succeeds for both plaintext and encrypted
>   entries without error (steps 12–15).

### Phase 3 — client2
18. Update client2 `Dockerfile` to accept and pass `EYED_MODE` build arg.
19. Create `lib/config/mode_config.dart`.
20. Create `lib/providers/fhe_provider.dart` (reads/toggles FHE via API).
21. Update `lib/app.dart` — add DEV badge and FHE toggle chip (dev mode only).
22. Update `lib/services/api_client.dart` — add `getConfig()` and `toggleFhe()`.
23. Add localisation strings for new UI elements.

> 🔒 **Security gate — Phase 3**
> - **S7** (Dart-Define Mode Tampering): build client2 with `EYED_MODE=dev`
>   but point it at a prod backend — confirm the FHE toggle UI is visible in
>   the browser, but `POST /engine/config/fhe` returns 404 from the server.
>   The UI toggle must not create any false sense of security.
> - **S4** (Mode Spoofing, client side): confirm that a prod-built client2
>   (no DEV badge, no toggle) cannot surface any dev-only UI regardless of
>   browser dev-tools manipulation — all checks are `const` dart-defines
>   compiled in at build time (step 18–19).

### Phase 4 — Verification
24. Test dev mode: toggle FHE off → enroll → verify template visible in gallery.
25. Test dev mode: toggle FHE on → enroll → verify "encrypted" badge, no preview.
26. Test prod mode (`make up`) → verify `POST /config/fhe` returns 404.
27. Test prod mode → verify `GET /config` returns no sensitive fields.
28. Test prod mode → verify `allow_plaintext=false`, templates always encrypted.
29. Test test mode → integration tests auto-start and pass.
30. Test FHE toggle persistence → restart container in dev → verify toggle state preserved.
31. Test database isolation → dev enroll → verify data only in `eyed_dev`, not in `eyed`.

> 🔒 **Security gate — Phase 4** (full regression)
> - Run all S1–S8 checks in sequence against a clean deployment.
> - Any failure blocks release.

---

## 5  Test Plan

### Unit Tests (iris-engine2)
| # | Test | Expected |
|---|---|---|
| T1 | `Config::from_env()` with `EYED_MODE=prod` and no `EYED_ALLOW_PLAINTEXT` | `allow_plaintext=false` |
| T2 | `Config::from_env()` with `EYED_MODE=dev` and no explicit overrides | `allow_plaintext=true`, `fhe_enabled=true` |
| T3 | `Config::from_env()` with `EYED_MODE=prod` + `EYED_ALLOW_PLAINTEXT=true` | explicit override wins: `allow_plaintext=true` |

### API Tests (iris-engine2, via curl / integration)
| # | Test | Expected |
|---|---|---|
| A1 | `GET /config` in dev mode | Returns full config with `mode: "dev"` |
| A2 | `GET /config` in prod mode | Returns only `gallery_size`, `db_connected`, `version` — no `mode`, no `fhe_active`, no sensitive fields |
| A3 | `POST /config/fhe {"enabled":false}` in dev mode | 200, FHE toggled off |
| A4 | `POST /config/fhe` in prod mode | **404 Not Found** |
| A5 | Enroll with FHE off (dev) → `GET /gallery/template/:id` | `is_encrypted=false`, `iris_code_b64` present |
| A6 | Enroll with FHE on → `GET /gallery/template/:id` | `is_encrypted=true`, `iris_code_b64=null` |

### Client2 Tests (manual / widget test)
| # | Test | Expected |
|---|---|---|
| C1 | Build with `EYED_MODE=dev` | FHE toggle visible in AppBar |
| C2 | Build with `EYED_MODE=prod` | No FHE toggle, no DEV badge |
| C3 | Toggle FHE off in dev → open gallery detail | Iris/mask code images displayed |
| C4 | Toggle FHE on in dev → open gallery detail | "Encrypted — no preview" notice |

### End-to-End
| # | Test | Expected |
|---|---|---|
| E1 | `make up-dev` → full workflow | All logs at debug, FHE toggle works |
| E2 | `make up-prod` → full workflow | Warn-only logs, no toggle endpoint, encrypted enrollment |
| E3 | `make up-test` → integration tests pass | Tests run with configurable FHE |

---

## 6  Security Concerns & Resolutions

### S1: FHE Toggle Endpoint in Production
- **Risk:** An attacker disables FHE, causing plaintext template storage.
- **Resolution:** `POST /config/fhe` is **not registered** when `mode == "prod"`.
  The endpoint literally does not exist — returns 404.  No auth bypass possible.

### S2: Config Endpoint Leaks Sensitive Data
- **Risk:** `GET /config` could expose `db_url`, `he_key_dir`, `db_name` in production.
- **Resolution:** In prod mode, **omit** all sensitive and inferrable fields
  entirely (not redacted — absent).  The prod response contains only:
  `gallery_size`, `db_connected`, `version`.  No mode, no FHE status,
  no database names, no key paths, no placeholders, no hints.

### S3: Plaintext Templates in Dev Database
- **Risk:** Dev database contains unencrypted iris templates; accidental
  cross-contamination between environments.
- **Resolution:**
  - Each mode uses a **dedicated database**: `eyed_dev`, `eyed_test`, `eyed` (prod).
  - The init scripts create all three databases; `EYED_DB_NAME_FILE` secret
    (or `EYED_MODE`-derived default) selects which one iris-engine2 connects to.
  - Complete data isolation: dev plaintext templates can never appear in prod.
  - Add a warning banner in client2 when viewing plaintext templates (dev mode).
  - Database name mapping:
    - `dev`  → `eyed_dev`
    - `test` → `eyed_test`
    - `prod` → `eyed`

### S4: Mode Spoofing via Environment Variable
- **Risk:** Attacker sets `EYED_MODE=dev` on a prod deployment.
- **Resolution:** In containerised deployments, env vars are set in
  `docker-compose.yml` and not user-controllable.  `docker-compose.prod.yml`
  hardcodes `EYED_MODE=prod` as an override — even if `.env` is tampered with,
  the prod override file wins.

### S5: Secrets in Git
- **Risk:** `secrets/` directory committed to version control.
- **Resolution:** Add `.gitignore` with `secrets/` and `.env` entries.
  Verify with `git status` after creation.

### S6: Log Verbosity in Production
- **Risk:** Debug logs expose PII (identity names, template metadata).
- **Resolution:** Prod mode sets spdlog to `warn`.  iris-engine2 `std::cout`
  startup messages are acceptable (no PII).  Request logging should not
  include identity names at warn level.

### S7: Dart-Define Mode Tampering
- **Risk:** Someone rebuilds client2 with `EYED_MODE=dev` against a prod backend.
- **Resolution:** The client2 mode only controls UI visibility (toggle, badge).
  The actual security enforcement is **server-side**: prod iris-engine2 rejects
  `POST /config/fhe` with 404 regardless of what the client sends.
  **Security is never client-side only.**

### S8: Mixed-Mode Templates in Gallery
- **Risk:** Gallery contains both encrypted and plaintext templates after toggling.
- **Resolution:** This is expected and handled.  The gallery match logic already
  supports mixed templates (plaintext HD for plaintext entries, encrypted HD for
  encrypted entries).  The `is_encrypted` flag per template ensures correct
  handling.  No retroactive encryption is performed on toggle.

---

## 7  Files to Create / Modify

### New Files
| File | Purpose |
|---|---|
| `.env` | Optional; absent = prod. `EYED_MODE=dev` to unlock dev features (git-ignored) |
| `.env.example` | Template documenting `EYED_MODE` and all overridable vars |
| `.gitignore` | Ignore `.env`, `secrets/`, build artifacts |
| `docker-compose.prod.yml` | Prod override: hardcodes `EYED_MODE=prod`, keeps port mappings |
| `secrets/db_name_dev.txt` | Database name for dev mode (`eyed_dev`) |
| `secrets/db_name_test.txt` | Database name for test mode (`eyed_test`) |
| `iris-engine2/src/routes_config.cpp` | `GET /config`, `POST /config/fhe` |
| `iris-engine2/src/routes_config.h` | Header for above |
| `client2/lib/config/mode_config.dart` | Mode constants from dart-define |
| `client2/lib/providers/fhe_provider.dart` | FHE state + toggle API calls |

### Modified Files
| File | Change |
|---|---|
| `docker-compose.yml` | Add `EYED_MODE` env + build arg to all services |
| `Makefile` | Add `up` (alias for `up-prod`), `up-dev`, `up-prod`, `up-test` targets |
| `iris-engine2/src/config.h` | Add `mode` field, derive defaults, db name mapping |
| `config/init.sql` | Create all three databases: `eyed`, `eyed_dev`, `eyed_test` |
| `config/init-engine2.sh` | Apply schema to all three databases |
| `iris-engine2/src/main.cpp` | Set spdlog level, register config routes |
| `iris-engine2/CMakeLists.txt` | Add routes_config.cpp to sources |
| `iris-engine2/Dockerfile` | Accept `EYED_MODE` build arg |
| `iris-engine2/src/routes_gallery.cpp` | Use dynamic `config.fhe_enabled` for vis check |
| `client2/Dockerfile` | Accept and pass `EYED_MODE` build arg |
| `client2/lib/app.dart` | DEV badge + FHE toggle chip |
| `client2/lib/services/api_client.dart` | `getConfig()`, `toggleFhe()` methods |
| `client2/lib/l10n/app_en.arb` | New strings: fheToggle, devBadge, etc. |
| `client2/lib/l10n/app_ko.arb` | Korean translations for above |

---

## 8  Decisions (resolved)

1. **Test mode auto-starts integration-test container.** ✅
   `make up-test` uses `--profile test` which includes the integration-test service.

2. **FHE toggle persists across container restarts.** ✅
   iris-engine2 writes the toggle state to a file in a Docker-mounted volume
   (`/config/fhe_state`).  On startup, if the file exists and the mode allows
   toggling (dev/test), the saved state overrides the mode default.  In prod
   mode the file is ignored (FHE always ON).

3. **Prod mode uses `docker-compose.prod.yml` override with port mappings kept.** ✅
   `docker-compose.prod.yml` hardcodes `EYED_MODE=prod` for all services
   (immune to `.env` tampering) and retains all port mappings.  `make up-prod`
   and `make up` both use this override file.
