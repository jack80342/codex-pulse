# Codex Pulse

English | [简体中文](README.zh-CN.md)

## Overview

Codex Pulse is a macOS menu bar app for managing multiple Codex accounts. It displays quota usage and sends minimal model requests at server-reported reset times to start new five-hour usage windows.

- View real usernames, plans, remaining five-hour and weekly quotas, and reset times.
- Add, log in, reauthenticate, or remove accounts in the app, with no account count limit.
- Refresh manually, restore scheduling after restart or wake, and enable launch at login.
- Use Chinese or English, selected automatically from macOS preferred languages on launch.

The app runs on macOS 14 or later and automatically locates an installed Codex CLI.

Licensed under the [MIT License](LICENSE).

## How it works

### Account isolation and quota reads

Each account authenticates through Codex CLI's app-server using its own local `CODEX_HOME`. Usernames are retrieved from a read-only internal profile endpoint. Quota usage, window durations, and reset times come from the server; unavailable values remain unknown. Failed queries retain the last successful quota snapshot and mark it as outdated.

### Automatic requests

1. On launch, the app reads each account's quotas and checks its saved request checkpoint.
2. For an eligible account that has not been attempted in the current window, it sends one minimal model request. Reading quota alone does not start a usage window; the model request consumes quota.
3. After completion, it reads the server's next five-hour reset time and schedules the next check. An existing window keeps its original reset time.
4. Each attempt is recorded before sending. Manual refresh, restart, and wake reuse the checkpoint to avoid repeated attempts in the same window; missed windows do not trigger catch-up requests.
5. Automatic requests stop when weekly quota is exhausted and pause when authentication or quota information is unavailable. Exhausted five-hour quota waits for its reset. Duplicate entries for the same identity share quota, and only the first eligible entry sends automatic requests.

Quota queries and automatic requests each use at most three workers. Account management pauses refresh and scheduling until the operation finishes. Scheduling requires the app to be running, the Mac to be awake, and network access to be available.

### Local storage

Account credentials stay in separate local directories. Scheduling checkpoints are stored locally so they survive restarts. The app uses these isolated directories without changing the everyday Codex App's login state.
