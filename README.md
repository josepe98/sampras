# Sampras

A lightweight macOS menu bar app for monitoring and launching local development servers.

## What it does

Sampras lives in your menu bar and gives you at-a-glance visibility into whether your local backend and frontend servers are running. It polls a set of predefined ports every few seconds and shows you which ones are active, which process is running on each, and lets you start or stop servers with a single click — without ever opening a terminal.

### Features

- **Live port monitoring** — watches backend ports (8000–8002) and frontend ports (5173–5178) and updates the menu bar icon to reflect the current state
- **Process identification** — detects which project is running on each port and displays its name in the menu
- **One-click start/stop** — start a server by selecting it from a discovered list of local projects; stop it just as easily
- **Auto app discovery** — scans your home directory for projects with a Python/uvicorn backend or a Node/Vite frontend and surfaces them as launch options
- **Log access** — open the log file for any running server directly from the menu
- **Open in browser** — launch the active frontend in your default browser in one click

The monitored ports and discovery logic can be tailored to track any apps running on those ports — making Sampras adaptable to your own local development setup.

## Requirements

- macOS 14 (Sonnet) or later
- Backend apps: Python project with a `venv` containing `uvicorn`
- Frontend apps: Node project with a `frontend/package.json` and `npm run dev` support

## Building

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate
./build.sh
```

This builds the app and installs it to `~/Applications/Sampras.app`.
