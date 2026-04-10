# Hermes Control Interface

A self-hosted web dashboard for the Hermes AI agent stack. Provides a browser-based terminal, file explorer, session overview, cron management, system metrics, and an agent status panel — all behind a single password gate.

**Designed for:** Single-user local networks or reverse-proxied VPS deployments. Not a multi-tenant product.

---

## Features

- **Terminal** — Real PTY shell (node-pty) in the browser via xterm.js. Full ANSI colour, persistent session.
- **File Explorer** — Browse and edit files across configurable root directories. No upload/download friction.
- **Session Monitor** — Live view of Hermes sessions and cron jobs.
- **System Metrics** — CPU, memory, uptime. Event-driven updates via WebSocket (no polling).
- **Rate-Limited Auth** — 5 failed login attempts in 15 minutes → 15-minute lockout. Timing-safe password comparison. HMAC-signed session cookies.
- **Layout Persistence** — Dashboard panel arrangement saved to `~/.hermes/control-interface-layout.json`.

---

## Requirements

- **Node.js 20+**
- **npm**
- A Hermes installation on the same machine (optional — the dashboard works without it, some panels just show placeholder data)
- `hermes` on PATH (optional, for in-terminal command shortcuts)

---

## Quick Start

```bash
git clone https://github.com/xaspx/hermes-control-interface.git hermes-control-interface
cd hermes-control-interface
npm install          # or: bash install.sh (interactive setup)
cp .env.example .env
# Edit .env — set HERMES_CONTROL_PASSWORD and HERMES_CONTROL_SECRET
npm start
```

Open `http://localhost:10272`.

---

## First-Run Setup

Run the interactive setup script for guided configuration:

```bash
bash install.sh
```

This will:
1. Check Node.js version
2. Install npm dependencies
3. Generate a random password and secret (or reuse existing `.env`)
4. Optionally configure nginx HTTPS reverse-proxy
5. Optionally install a systemd service for auto-start

---

## Configuration

All settings are environment variables. See [docs/CONFIG.md](docs/CONFIG.md) for the full reference.

**Required:**
| Variable | Description |
|---|---|
| `HERMES_CONTROL_PASSWORD` | Login password |
| `HERMES_CONTROL_SECRET` | HMAC secret for auth tokens (generate with `openssl rand -hex 32`) |

**Optional:**
| Variable | Default | Description |
|---|---|---|
| `PORT` | `10272` | HTTP listen port |
| `HERMES_HOME` | `~/.hermes` | Hermes state directory |
| `HERMES_PROJECTS_ROOT` | parent of repo | Explorer projects root |
| `HERMES_CONTROL_ROOTS` | `HERMES_PROJECTS_ROOT` + `HERMES_HOME` | Explorer root overrides |

---

## Deployment

### Option A — Behind nginx reverse-proxy (recommended for VPS)

```bash
# In install.sh, answer Yes to the nginx prompt, or create manually:
# Proxy to http://127.0.0.1:10272 from your HTTPS server block.
# See docs/DEPLOY.md for a full example nginx config.
```

The dashboard must be served over HTTPS. The `Secure` cookie flag is always set.

### Option B — Direct on LAN (home network only)

Bind to `0.0.0.0` (default) and password-protect. Do not expose directly to the public internet without a reverse-proxy and TLS.

### Option C — systemd service

```bash
# After running install.sh:
sudo systemctl start hermes-control
sudo systemctl status hermes-control  # verify it's running
```

Auto-start on boot is enabled automatically if you installed via `install.sh`.

---

## Security Notes

- The password is compared using `crypto.timingSafeEqual` — no timing oracle.
- Auth cookies are HMAC-signed with a per-deployment secret. They expire after 24 hours.
- Rate limiting blocks an IP after 5 failed attempts in 15 minutes.
- The `Secure` cookie flag is always set. Access over HTTP only works on `localhost` — use HTTPS in production.
- File operations are scoped to configured explorer roots — path traversal out of allowed directories is blocked.
- No multi-user support. All browser sessions share the same password.

See [docs/SECURITY.md](docs/SECURITY.md) for the full security analysis.

---

## API Reference

| Method | Path | Auth | Description |
|---|---|---|---|
| `GET` | `/api/health` | No | Health check |
| `GET` | `/api/session` | No | Auth status |
| `POST` | `/api/login` | No | Login (rate-limited) |
| `POST` | `/api/logout` | No | Clear session |
| `GET` | `/api/dashboard-state` | Yes | Full dashboard snapshot |
| `GET` | `/api/explorer` | Yes | Directory tree |
| `GET` | `/api/file` | Yes | Read file |
| `POST` | `/api/file` | Yes | Write file |
| `POST` | `/api/terminal/exec` | Yes | Run terminal command |
| `POST` | `/api/cron/:action` | Yes | Manage cron jobs |
| `GET` | `/api/usage` | Yes | System metrics |
| `GET` | `/api/layout` | Yes | Get layout |
| `POST` | `/api/layout` | Yes | Save layout |
| `GET` | `/api/avatar` | Yes | Get avatar metadata (url + custom flag) |
| `GET` | `/api/avatar/image` | Yes | Get avatar image (raw binary, cacheable) |
| `POST` | `/api/avatar` | Yes | Upload avatar |
| `DELETE` | `/api/avatar` | Yes | Reset avatar |
| `WS` | `/ws` | Yes | Live dashboard updates + terminal I/O |

All authenticated endpoints require a valid session cookie (`hermes...auth`).

Internal endpoints (`/internal/cron/:action`) require the `x-hermes-control-secret` header matching `HERMES_CONTROL_SECRET`.

---

## Repo Layout

```
hermes-control-interface/
├── server.js          # Express server, auth, PTY, WebSocket, APIs
├── website/           # Frontend (vanilla JS, xterm.js)
├── docs/              # Detailed documentation
│   ├── CONFIG.md       # Environment variable reference
│   ├── SECURITY.md    # Security analysis
│   ├── DEPLOY.md      # Production deployment guide
│   └── API.md         # API endpoint details
├── .env.example       # Template — copy to .env
├── .env               # Runtime config (gitignored)
├── install.sh         # Interactive first-run setup
└── package.json
```

---

## Changelog

### v1.1.0 — Stability Fixes (2026-04-09)

**Avatar system rewrite:**
- Avatar served via dedicated `/api/avatar/image` endpoint (raw binary with cache headers)
- No more ~700KB base64 embedded in every WebSocket snapshot
- Client-side avatar image caching — no flicker on re-render

**Event-driven refresh (removed all polling):**
- Removed server-side 15-second broadcast interval (`setInterval(broadcast, 15000)`)
- Removed client-side 10-second session poller
- Snapshots only broadcast on actual state changes (avatar upload/delete, cron actions, terminal events)
- Manual refresh button still works for full state reload

**Smart rendering:**
- Change detection on all panels — DOM only rebuilds when data actually changed
- File explorer scroll position preserved across re-renders
- Sessions list stable during avatar upload (no "no sessions found" flash)
- Sprite animation loop skips when custom avatar is loaded

---

## Roadmap

Improvements grouped by dependency and parallelism (from senior software engineer audit):

### Group 1 — Security + Password (Do together)
- [ ] bcrypt password hashing (replace plaintext env)
- [ ] reset-password CLI command
- [ ] reset-password bash script
- [ ] Non-root systemd user

Why together: all touch auth/server config, one restart done.

### Group 2 — Code Refactor (Do together)
- [ ] Split server.js into modules (1250+ line monolith)
- [ ] Replace `execFileSync` → `execFile` (async, non-blocking)
- [ ] Remove dead code (renderBackground hardcode, offlineReply dummy, placeholder cronJobs)
- [ ] Fix variable naming collision (`state` parameter vs global)
- [ ] YAML config parsing (replace regex with proper parser)

Why together: all touch server.js, doing one-by-one causes conflicts.

### Group 3 — Open Source Docs + Config (Do together, parallel with Group 2)
- [ ] CONTRIBUTING.md
- [ ] CODE_OF_CONDUCT.md
- [ ] Issue templates (.github/)
- [ ] ESLint / Prettier config

Why together: pure new files, doesn't interfere with code.

### Group 4 — DevOps (After Group 2)
- [ ] Dockerfile
- [ ] CI/CD (GitHub Actions)

Why together: Dockerfile needs final structure from Group 2. CI/CD needs test suite + lint config.

### Group 5 — Testing (After Group 2)
- [ ] Test suite minimal (auth, path traversal, API endpoints)

Why last: tests written for already-refactored code.

### Group 6 — Performance (Anytime)
- [ ] Sessions Map eviction (memory leak prevention)
- [ ] WebSocket connection timeout/cleanup

Why independent: doesn't interfere with others.

### Execution Order

```
Group 1 (Security)              ← start first, low impact
    ↓
Group 2 + Group 3 (parallel)    ← refactor code + docs together
    ↓
Group 4 + Group 5 (parallel)    ← Docker + CI + test
    ↓
Group 6 (Performance)           ← anytime
```

## Troubleshooting

**502 Bad Gateway**
The Node.js process isn't running. Check that `.env` exists and has valid `HERMES_CONTROL_PASSWORD` / `HERMES_CONTROL_SECRET` values.

```bash
cd hermes-control-interface
node server.js
# Look for startup errors
```

**"authentication required" after login**
The cookie wasn't accepted. Check that you're accessing the dashboard over HTTPS (required for `Secure` cookies), or that your reverse-proxy is forwarding cookies correctly.

**Port already in use**
Change the port: `PORT=10702 npm start` or set `PORT=10702` in `.env`.

**Terminal not connecting**
Make sure `node-pty` compiled successfully. On some systems you may need `make` and a C++ compiler.

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for more.
