# Prototype scenario tests (ticket E1-11)

Automated scenario suite for the mta + imap prototype. Runs against the real
Docker Compose stack (no mocks).

## Layout

```
prototype/tests/
├── run-all.sh              single entry point
├── README.md               this file
├── lib/
│   ├── sink.sh             Mailpit sink helpers (E1-02)
│   ├── mail.sh             shared helpers: reset, send, IMAP, queue
│   ├── smtp_send.py        SMTP test sender (python3 smtplib, swaks-compatible flags)
│   └── imap_check.py       IMAP test helper (count / read / wait)
└── scenarios/
    ├── 01_relay_main_up.sh
    ├── ...
    └── 20_empty_config_starts_cleanly.sh
```

## Prerequisites

- `docker compose up -d --build` has been run (mta, imap, main services running).
- `python3` with `smtplib` / `imaplib` available on the host (used by the helpers).
- `curl` available for the sink helpers.

## Usage

```
prototype/tests/run-all.sh                # all scenarios, expect all pass
prototype/tests/run-all.sh --only 08     # catch-all scenario only
prototype/tests/run-all.sh --keep        # leave the stack running after the run
```

## Interpreting failures

- Each scenario resets state first (empty sink, empty queue, empty mailboxes).
- `run-all.sh` prints one line per scenario: PASS or FAIL with its name, plus a
  summary and a non-zero exit code if any scenario fails.
- On failure, the scenario prints relevant evidence (via `pass`/`fail` helper and
  the underlying helper output).

## Adding a scenario

1. Add `prototype/tests/scenarios/NN_<name>.sh` which sources
   `../lib/mail.sh`, calls `reset_state`, runs the checks and reports via
   `pass`/`fail`.
2. Add the scenario number to the ordered list expectation in `run-all.sh`
   (scenarios are picked up by sorted glob `NN_*`).
3. Update the scenario table in `sdlc/components/mta_imapd/tickets/E111.md` if
   needed.

## Determinism notes

- No sleeps longer than needed; helpers `wait_for_sink` and `imap_wait_ready`
  poll with timeouts (the common source of flaky tests).
- Scenarios must not share state; each resets state first.
