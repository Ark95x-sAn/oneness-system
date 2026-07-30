# Prime CLI

Prime Fire Council command center for the Oneness System.

## Install

```bash
cd prime-cli
uv pip install -e . --system
# or: pip install -e .
```

## Usage

```bash
prime --help
prime doctor
prime start
prime status --json
prime agents list
prime fix
prime auth
prime service-install
prime web
```

## Commands

- `doctor` — diagnose system readiness
- `start` — launch web dashboard + orchestrator
- `stop` — stop Oneness processes
- `status` — show live system status
- `agents list|tick` — list or tick agents
- `projects list|scan|build` — manage VS projects
- `fix` — run all fixer agents
- `auth` — launch authentication helpers
- `service-install` — install Windows service (admin UAC)
- `web` — open dashboard URL
- `skill-install <path>` — install a skill from openai/skills
- `review <path>` — lightweight static review

## Auth

Place secrets in `C:\Users\ArcXN\OneDrive\Desktop\OnenessSystem\.env`.
