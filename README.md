# Crucible

> **Status:** Phase 0 — repository scaffold. Not yet runnable. See
> [`CLAUDE.md`](./CLAUDE.md) for the canonical specification and phase plan.

Crucible is a single-binary, ephemeral, cross-platform CLI that runs on a
production server alongside an active workload, observes it for a configurable
window, fingerprints it across every relevant resource dimension, and produces
a **vendor-neutral hardware recommendation** describing the hardware
*characteristics* that would run the same workload better.

The output is not a SKU list. It answers questions like:

- Does this workload want **high single-thread clock** or **many parallel cores**?
- Does it want **lots of RAM at modest speed** or **less RAM at high bandwidth**?
- Is it storage-bound? **High-IOPS NVMe**, **high-throughput sequential SSD**, or would HDD suffice?
- Would a GPU help? If yes, **VRAM-priority** or **compute-priority**?
- Bare metal, or **safe to virtualize** (with what expected performance hit)?
- If multiple workloads share the host: **consolidate** or **split** — and what specs for each option?

The end user is a sysadmin or infrastructure architect who runs Crucible on a
candidate server, lets it observe the live workload for 24 hours, and walks
away with a defensible written recommendation they can use to **build a new
server from scratch**.

---

## Non-negotiable properties

1. **Zero meaningful impact on the host workload** (<1% of a core averaged, <100 MB RAM, batched disk writes, no fsync storms).
2. **Ephemeral.** Install → run → export → `crucible uninstall` leaves no trace.
3. **Single static Go binary.** No runtime deps, no Python, no shared libraries beyond the OS.
4. **Production-grade from day one.** Errors handled on every syscall, structured logging, context propagation, no panics in library code, CI green before any phase closes.
5. **Stable, versioned JSON output schema** — treated as a public API from v1.
6. **Rule-based deterministic recommender.** No LLM calls at runtime in v1.

Full constraints in [`CLAUDE.md` §2](./CLAUDE.md).

---

## Project layout

```
.
├── CLAUDE.md                # Source-of-truth spec; read first
├── LICENSE                  # BSL 1.1 (TBD; full text added in Phase 0)
├── LICENSING.md             # Plain-English license guidance
├── LICENSE-HEADER.txt       # SPDX header every Go file must carry
├── Makefile                 # Build, test, lint, cross-compile entry points
├── README.md
├── cmd/
│   └── crucible/            # main package — single binary entry point
├── docs/
│   └── architecture.md      # Data-flow diagram and layer contracts
├── internal/
│   ├── cli/                 # cobra commands
│   ├── collectors/          # Raw metric gathering, OS-specific
│   ├── analyzers/           # Raw metrics → workload fingerprint
│   ├── recommenders/        # Fingerprint → hardware recommendation
│   ├── detect/              # OS / distro / virt / container detection
│   ├── report/              # JSON/Markdown/PDF rendering
│   ├── delivery/            # HTTPS upload + SMTP relay
│   ├── storage/             # SQLite-backed local run state
│   └── version/             # Build-stamped version metadata
├── pkg/
│   └── schema/              # Versioned, public structs (fingerprint, report)
├── rules/
│   └── v1/                  # YAML rule set for the deterministic recommender
├── signatures/              # YAML workload-identification patterns
├── scripts/                 # Build / release / dev helpers
└── .github/workflows/       # CI: lint, vet, test, race, cross-compile, govulncheck
```

The three-layer separation (`collectors` → `analyzers` → `recommenders`) is
load-bearing. See [`docs/architecture.md`](./docs/architecture.md).

---

## Building (placeholder)

The Go toolchain is required (Go 1.23+). Once Phase 0 ships, the canonical
commands will be:

```bash
make build         # build for the current OS/arch into ./bin/
make test          # go test ./... with race detector
make lint          # golangci-lint + go vet + gofmt -d
make cross         # cross-compile linux/amd64, linux/arm64, windows/amd64
make clean
```

CI (GitHub Actions) is the authoritative build environment until Phase 12 QA.
Local builds are a convenience.

---

## Running (placeholder — not yet implemented)

```
crucible doctor              # Capability detection: kernel, eBPF, PMU, GPU, perms
crucible run --window 24h    # Observe for 24 hours, write report to ./out
crucible status              # Progress of a running session
crucible report              # Re-render a completed run's artifacts
crucible uninstall           # Remove binary, temp data, systemd units, logs
crucible version
```

Full flag surface and config-file/environment-variable precedence are
documented in `CLAUDE.md` §5 and will be reproduced in `docs/cli.md` in
Phase 0 close-out.

---

## Output

Every run produces, locally:

- `report.json` — full structured data, versioned schema (`schema_version: "1.0.0"`).
- `report.md` — human-readable Markdown.
- `report.pdf` — PDF render of the Markdown.
- `summary.txt` — terminal executive summary.

Optional delivery channels (both may be enabled simultaneously; failure of
either does not invalidate the local report):

- `--upload-url … --upload-token …` — HTTPS POST with bearer token, optional mTLS.
- `--email-to … --smtp-config …` — PDF attachment via SMTP relay.

---

## Phase status

| Phase | Scope | State |
| --- | --- | --- |
| 0 | Repo scaffold, CI, license, docs skeleton | **In progress** |
| 1 | Detection framework + `crucible doctor` | Not started |
| 2 | Linux CPU + scheduler collectors | Not started |
| 3 | Linux memory + NUMA | Not started |
| 4 | Linux disk + network | Not started |
| 5 | GPU collectors | Not started |
| 6 | Workload identification | Not started |
| 7 | Windows port | Not started |
| 8 | Recommendation engine | Not started |
| 9 | Report generation | Not started |
| 10 | Secure delivery | Not started |
| 11 | Installer / uninstaller | Not started |
| 12 | End-to-end QA on synthetic workloads | Not started |
| 13 | v1.0 release | Not started |

The full plan lives in [`CLAUDE.md` §6](./CLAUDE.md). Phases are not
bundled; each closes with a summary and waits for explicit approval before
the next begins.

---

## License

Crucible is licensed under the **Business Source License 1.1** with an
Additional Use Grant. The license automatically converts to **Apache 2.0**
on **2030-05-13**.

- Internal use (including commercial) is free.
- Offering Crucible itself as a hosted service to third parties before the
  Change Date requires a commercial license.

See [`LICENSING.md`](./LICENSING.md) for the plain-English summary and
[`LICENSE`](./LICENSE) for the controlling legal text.

---

## Contributing

Until v1.0, the project is being built in disciplined, gated phases. External
contributions are welcome as issues and discussion; PRs against
phase-in-progress code will be triaged but may be deferred to the appropriate
phase boundary. New collectors, rules, and signatures are the easiest places
to contribute meaningfully without crossing phase work.

Source files must carry the SPDX header in [`LICENSE-HEADER.txt`](./LICENSE-HEADER.txt).
CI enforces this.
