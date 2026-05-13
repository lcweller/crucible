# CLAUDE.md — Crucible Project Source of Truth

> This file is the canonical specification, locked decisions, and phase log
> for the Crucible project. Claude Code reads this file at the start of
> every session. Update it as the project evolves; treat it as the contract.

---

## 1. Mission

Crucible is a **single-binary, ephemeral, cross-platform CLI tool** that runs
on a production server alongside an active workload, observes it for a
configurable window, fingerprints it across every relevant resource dimension
(CPU, memory, disk, network, GPU, scheduling behavior, NUMA locality,
virtualization context), and produces a **vendor-neutral hardware
recommendation** describing the hardware *characteristics* that would run the
same workload better.

The output is not a list of SKUs. The output answers:

- Does this workload want **high single-thread clock** or **many parallel cores**?
- Does it want **lots of RAM at modest speed** or **less RAM at high bandwidth**?
- Is it **storage-bound**? If so, **high-IOPS NVMe**, **high-throughput sequential SSD**, or would **HDD suffice**?
- Would a **GPU** help? If yes, **high VRAM / low TFLOPs** (large model inference, video transcode) or **low VRAM / high TFLOPs** (compute-heavy)?
- Should it stay **bare metal** or is it **safe to virtualize**? Expected performance hit if virtualized?
- If multiple workloads share the host, should they be **consolidated** on one machine or **split** into purpose-built boxes? Specs for both, with a recommendation and rationale.

End user: a sysadmin / infrastructure architect who runs Crucible on a
candidate server, lets it observe the live workload for 24 hours, and walks
away with a defensible written recommendation they can use to **build a new
server from scratch** — not buy one off a vendor catalog.

---

## 2. Non-Negotiable Constraints

These are inviolable. If a design decision conflicts with any, the constraint wins.

1. **Zero meaningful impact on the host workload.** Crucible's own CPU usage <1% of a single core averaged over the sampling window. Resident memory <100 MB. Disk writes batched and rate-limited. No fsync storms. No kernel module loading unless eBPF requires it, and only with explicit user consent.
2. **Ephemeral by design.** Clean install → run → upload/export → remove. `crucible uninstall` is first-class and removes binary, all temp data, systemd units, log files, Windows registry entries. **Leave no trace.**
3. **Root / Administrator assumed.** Do not design for unprivileged operation in v1. Fail fast with a helpful error if not elevated.
4. **Single static binary.** No runtime deps. No Python, no Node, no shared libraries beyond what the OS provides. Cross-compile Linux (amd64, arm64) and Windows (amd64) from a single Go module.
5. **Graceful capability degradation.** If eBPF unavailable → fall back to `/proc` and `perf_event_open`. If PMU counters inaccessible → note in report and continue. Never crash; always degrade and document what was lost.
6. **Production-grade from day one.** Error handling on every syscall. Structured logging (`log/slog`). Context propagation everywhere. No `panic` in library code. Tests on every collector. CI green before any phase is considered done.
7. **Stable output schema.** The JSON report schema is versioned (`schema_version: "1.0.0"`) and treated as a public API from v1 forward. Future Crucible versions must remain backward-compatible consumers.

---

## 3. Locked Tech Stack

Do not deviate without flagging and waiting for approval.

| Concern | Choice |
| --- | --- |
| Language | Go 1.23+ (latest stable at start of build) |
| Build | Go modules, single binary via `go build`, cross-compile via `GOOS`/`GOARCH` |
| CLI framework | `cobra` + `viper` for config |
| Logging | `log/slog` — JSON to file, human-readable to stderr |
| Local storage during run | Embedded SQLite (`modernc.org/sqlite` — pure Go, no CGO) in `/var/tmp/crucible-<runid>/` (Linux) or `%TEMP%\crucible-<runid>\` (Windows). Deleted at end of run unless `--keep-raw`. |
| Linux metrics | eBPF (`cilium/ebpf`), `perf_event_open` for PMU, `/proc` and `/sys` parsers, `ss`/`ip`/`ethtool` where needed. Priority + fallback order. |
| Windows metrics | ETW, Performance Data Helper (PDH), WMI, GPU vendor APIs |
| GPU | NVIDIA `NVML`, AMD `rocm-smi`, Intel `intel_gpu_top` / Level Zero |
| Report rendering | Markdown in-tool; PDF via `chromedp` headless Chrome or `wkhtmltopdf` fallback — final choice locked in Phase 8 with justification |
| Secure delivery | HTTPS POST with bearer token (optional mTLS upgrade); SMTP relay with PDF attachment |
| Linting | `gofmt`, `golangci-lint` with the strict ruleset committed to the repo |
| Testing | Standard `testing`, table-driven, `testify` assertions, integration tests gated by build tags |
| CI | GitHub Actions — lint, vet, test, race, cross-compile matrix, `golangci-lint`, `govulncheck` |
| License | **Business Source License 1.1**. Change Date = 2030-05-13. Change License = Apache 2.0. Additional Use Grant restricting commercial hosted/SaaS use of Crucible itself. See `LICENSE`, `LICENSING.md`, `LICENSE-HEADER.txt`. |

---

## 4. Architecture Principles

Crucible must be architected so future phases (web dashboard, fleet
aggregation, continuous monitoring, what-if simulation, historical trend
analysis) drop in without rewrites.

- **Three-layer separation**:
  1. `internal/collectors/` — gather raw metrics; OS-specific.
  2. `internal/analyzers/` — turn raw metrics into a workload fingerprint; OS-agnostic.
  3. `internal/recommenders/` — turn a fingerprint into a hardware recommendation; OS-agnostic and deterministic.
- **Plugin-style collectors**: each collector implements a common `Collector` interface so new metric sources / new OSes are additive, not invasive.
- **Plugin-style rules**: the recommendation engine is a deterministic rule set defined in versioned YAML under `rules/v1/*.yaml` plus a Go evaluator. Rules are added, modified, and unit-tested independently of the engine.
- **Stable intermediate schema**: the workload fingerprint is a versioned struct serializable to JSON (`pkg/schema/`). Future LLM-assisted recommenders, web dashboards, and what-if simulators all consume this same schema.
- **No global state.** Everything threads through `context.Context` and explicit dependency injection.
- **Configurable everything** via flags + config file + env vars, in that precedence order (highest → lowest).

See `docs/architecture.md` for the data-flow diagram.

---

## 5. Functional Scope for v1

### 5.1 Platform support

- Linux server distros: RHEL 8/9, Rocky 8/9, AlmaLinux 8/9, Ubuntu Server 22.04/24.04 LTS, Debian 12, SUSE Linux Enterprise Server 15, openSUSE Leap 15.
- Windows Server 2019, 2022, 2025.
- Auto-detect bare metal vs. VM (KVM, VMware, Hyper-V, Xen) vs. container (Docker, containerd, LXC, Kubernetes pod). When inside a VM/container, the report must disclose the limitation and note what telemetry could not be observed (e.g., true PMU counters from inside a VM are often virtualized and unreliable).

### 5.2 Workload identification (three layered approaches)

1. **Process signatures** — a maintained catalog in `signatures/*.yaml` of known process-name + port + cgroup + parent-process patterns (Postgres, MySQL/MariaDB, Redis, nginx, Apache, Node, .NET, Tomcat, Java app servers, KVM/QEMU instances, ffmpeg, Elasticsearch, MinIO, Samba, dedicated game servers, ML inference servers, …).
2. **User-supplied tags** — `--tag PID=1234:my-database` lets the operator label processes Crucible should treat as the primary subject.
3. **Heuristic behavioral classification** — for unknown processes, cluster by resource fingerprint (CPU pattern, I/O pattern, syscall mix, network pattern) and label with a generated descriptor like "CPU-bound batch worker, single-threaded, low I/O".

The signature catalog is a starting hint, not a requirement. **Crucible must work and produce a recommendation even when every process is unknown.** Behavioral classification is the foundation; signatures are shortcuts.

### 5.3 Metrics collected (per identified workload AND at the host level)

- **CPU**: per-core utilization, single-thread saturation %, IPC, branch mispredict rate, L1/L2/LLC cache miss rate, run-queue length, context switch rate (voluntary vs. involuntary), scheduler latency, NUMA cross-socket traffic, CPU steal time (if virtualized), turbo residency.
- **Memory**: RSS, working set, anon vs. file-backed split, page fault rate (major + minor), memory bandwidth utilization via PMU uncore counters when available, NUMA node locality, swap pressure, transparent hugepage usage, attributable slab consumption.
- **Disk I/O**: per-device IOPS read/write, throughput read/write, latency p50/p95/p99, queue depth, sequential vs. random ratio, sync vs. async writes, fsync frequency.
- **Network**: throughput in/out, packets-per-second in/out, active TCP connections, new connections per second, TCP retransmit rate, RTT distribution, listen socket backlog depth.
- **GPU**: utilization (compute + memory copy), VRAM used, memory bandwidth, FP32/FP16/INT8 TFLOPs utilized, PCIe bandwidth, power draw, temperature, per-process attribution.
- **Power & thermal**: RAPL package counters where available, IPMI sensors if accessible (best-effort).

### 5.4 Sampling strategy

- **Burst** — 1 s sampling for first 60 s to catch cold-start transients.
- **Steady** — 15 s sampling for the remainder (default).
- All intervals configurable via `--burst-interval`, `--burst-duration`, `--steady-interval`.
- **Snapshot mode** (`--snapshot`) = degenerate 60 s window at 1 s sampling.
- Window length via `--window 1h | 24h | 7d | <duration>`. Default `24h`.

### 5.5 Recommendation engine

- **Deterministic, rule-based.** **No LLM calls at runtime in v1.** All inference happens locally via Go code and YAML rules. Hard requirement.
- Output per workload (plus one composite for the whole host):
  - **CPU**: thread profile (single-thread-heavy / balanced / many-thread-heavy), recommended core count range, recommended base/boost clock range, ISA features that matter (AVX-512, AMX, …, if observed in use).
  - **Memory**: capacity range, capacity-priority vs. bandwidth-priority, ECC required (yes for any server use), NUMA topology recommendation (single-socket vs. dual-socket, with rationale).
  - **Storage**: medium (NVMe Gen4/Gen5 / SATA SSD / HDD), capacity, IOPS profile, sequential throughput profile, RAID/redundancy, hot vs. cold tiering hints.
  - **Network**: NIC speed (1/10/25/40/100 GbE), offload features (RSS, TSO, RDMA).
  - **GPU**: needed / not needed; if needed, characteristics (VRAM-priority vs. compute-priority, FP precision, PCIe gen, NVLink relevance).
  - **Virtualization verdict**: bare-metal-required / safe-to-virtualize / safe-with-caveats, with expected percentage performance impact, citing the specific telemetry signals.
  - **Topology**: single-server-fits-all vs. split-recommended, with per-split specs.
- **Three tiers** per workload: **Budget** (minimum acceptable), **Balanced** (recommended sweet spot), **Performance** (no-compromise). Each tier carries rationale.
- **Confidence score** per recommendation (0–100) with explicit drivers ("Window of only 1 h limits confidence; bursty workload not fully characterized; PMU counters unavailable").

### 5.6 Report output

Always written locally:

- `report.json` — full structured data, versioned schema, canonical.
- `report.md` — human-readable Markdown.
- `report.pdf` — PDF render of the Markdown.
- `summary.txt` — terminal-printable executive summary.

Sections, in order:

1. **Executive Summary** — 1-paragraph headline + tier table.
2. **Host Baseline** — current hardware, OS, virtualization context.
3. **Detected Workloads** — list, classification method, confidence.
4. **Per-Workload Resource Fingerprint** — full metric profile with embedded charts (PNG in PDF).
5. **Recommended Hardware** — three tiers per workload + composite if multi-workload.
6. **Reasoning** — which signals drove which conclusions, with cited rule IDs from the rule YAML.
7. **Virtualization Analysis** — verdict + projected impact.
8. **Multi-Workload Topology** — consolidate vs. split, specs for both, recommendation.
9. **Risks, Caveats, and Confidence** — what we couldn't measure, what would raise confidence, what to re-run.
10. **Raw Data Appendix** — sampled metric summaries (full raw data only via `--keep-raw`).

### 5.7 Report delivery

Local artifacts are always written and are the source of truth. Optional channels:

- `--upload-url https://reports.example.com/ingest --upload-token $TOKEN` — POST `report.json` + `report.pdf` with `Authorization: Bearer $TOKEN`. mTLS optional via `--client-cert` / `--client-key`.
- `--email-to ops@example.com --smtp-config /etc/crucible/smtp.yaml` — send the PDF as an attachment via configured SMTP relay.
- Both may be enabled simultaneously. Failure of either does not invalidate the local report.

### 5.8 Lifecycle commands

```
crucible run        [--window 24h] [--output ./out] [--upload-url …] [--email-to …]
crucible status     # progress of a running session
crucible report     # re-render a completed run's artifacts
crucible uninstall  # remove binary, temp data, systemd units, logs — leave no trace
crucible doctor     # kernel version, eBPF support, PMU access, GPU drivers, perms
crucible version
```

`crucible doctor` is mandatory. It runs all capability detection and prints
exactly what Crucible will and will not be able to measure on this host
**before** the user commits to a 24-hour run.

---

## 6. Phased Build Plan

> **Stop at the end of each phase**, summarize what shipped, run the test
> suite, and wait for explicit approval before starting the next phase. Do
> not bundle phases.

| Phase | Scope |
| --- | --- |
| **0** | Repo scaffold. `go.mod`, directory structure, `CLAUDE.md`, `LICENSE` (BSL 1.1), `LICENSING.md`, `README.md` skeleton, `.gitignore`, `.golangci.yml`, GitHub Actions CI matrix (lint/vet/test/build for linux-amd64, linux-arm64, windows-amd64), `Makefile`, version stamping via `-ldflags`. CI green. |
| **1** | Detection framework. OS detection, distro detection, kernel version, virtualization detection (DMI, CPUID, `/sys/class/dmi`, hypervisor leaf), container detection (cgroup, `/.dockerenv`, …), hardware baseline inventory (CPU model, core/thread counts, memory size + topology, NUMA, disks, NICs, GPUs). `crucible doctor` ships here. |
| **2** | Linux CPU + scheduler collectors. `/proc/stat`, `/proc/schedstat`, perf PMU via `perf_event_open`, IPC, cache miss rates, run-queue depth. Unit + integration tests. |
| **3** | Linux memory + NUMA. `/proc/meminfo`, `/proc/<pid>/status`, `/sys/devices/system/node/`, uncore memory bandwidth counters where available, NUMA locality. |
| **4** | Linux disk + network. `/proc/diskstats`, `/sys/block/`, blktrace-equivalent latency via eBPF when available, `/proc/net/dev`, `ss` for socket stats, retransmit counters. |
| **5** | GPU collectors. NVIDIA NVML → AMD ROCm SMI → Intel Level Zero. Per-process attribution. |
| **6** | Workload identification. Signature catalog (YAML), tag parsing, behavioral classifier. Generate fingerprint struct (stable schema). |
| **7** | Windows port of all collectors. ETW + PDH + WMI. Feature parity for CPU/memory/disk/network; document GPU caveats. |
| **8** | Recommendation engine. Rule YAML schema, evaluator, three-tier output, confidence scoring, virtualization verdict, multi-workload topology decision. Unit tests per rule. |
| **9** | Report generation. JSON (canonical), Markdown, PDF (final choice locked here with justification), terminal summary, embedded charts. |
| **10** | Secure delivery. HTTPS POST with bearer + optional mTLS, SMTP relay with PDF attachment. Retry/backoff. Failure does not invalidate the local report. |
| **11** | Installer/uninstaller. One-line installers — Linux (`curl … \| sh` to `/usr/local/bin` with checksum verification) and Windows (PowerShell, Authenticode-signed once we have a cert). `crucible uninstall` proven clean by integration test. |
| **12** | End-to-end QA on synthetic workloads (CPU-bound single-thread, CPU-bound parallel, memory-bandwidth-bound, IOPS-bound, throughput-bound, GPU-bound, mixed). Verify recommendations are sane and defensible. |
| **13** | v1.0 release. Tag, GitHub Release with cross-compiled binaries + checksums + SBOM, finalized README/LICENSING.md, public announcement copy. |

### Phase 0 status — IN PROGRESS

- [x] Directory scaffold (`cmd/`, `internal/`, `pkg/schema/`, `signatures/`, `rules/v1/`, `docs/`, `scripts/`, `.github/workflows/`)
- [x] `go.mod`, `cmd/crucible/main.go`, `internal/cli/` stubs + smoke test
- [x] `CLAUDE.md` (this file)
- [ ] `LICENSE`, `LICENSING.md`, `LICENSE-HEADER.txt`
- [ ] `README.md` skeleton
- [ ] `docs/architecture.md` with Mermaid diagram
- [ ] `.gitignore`, `.golangci.yml`, `Makefile`
- [ ] `.github/workflows/ci.yml` — lint/vet/test/race/cross-compile/govulncheck matrix
- [ ] Local Go build & test verification *(deferred — Go toolchain not installed on the local host; CI will validate)*
- [ ] Phase 0 completion summary posted; **stop and await approval**

---

## 7. Process Expectations

- **Start of every phase**: post a short plan — scope, files to touch, test strategy, risks. Wait for approval.
- **When uncertain about a design decision**: stop and ask. Do not guess. Do not invent requirements. Examples of things to **ask, not assume**: rule thresholds (what IPC counts as "high"?), behavioral classifier cluster boundaries, which signatures ship in v1's catalog, virtualization performance-impact percentages.
- **End of every phase**: post a summary — what shipped, what tests pass, what is deferred, what changed in `CLAUDE.md`.
- **Never commit broken code.** CI green before phase close.
- **Update `CLAUDE.md`** as the project's source of truth — locked decisions, schema versions, deferred work, any deviations from this initial spec.

---

## 8. Quality Bar

- Every collector has unit tests with fixture data (sample `/proc/stat` outputs, sample WMI responses, …).
- Every recommendation rule has at least one unit test asserting it fires and at least one asserting it does not fire when it shouldn't.
- Integration tests use Docker containers and synthetic workload generators (`stress-ng`, `sysbench`, `fio`, `iperf3`) on Linux. Windows uses native synthetic load tools.
- `golangci-lint` clean. `go vet` clean. `govulncheck` clean. Race detector clean on all tests.
- The public API (JSON schema, rule YAML schema, CLI flags) is documented in `docs/`.

---

## 9. Open Questions / Deferred Decisions

Tracked here so phase boundaries don't drift. Each item must be resolved at
its phase or earlier — never silently assumed.

- **Phase 8**: numeric thresholds for the rule engine (e.g., IPC cutoffs, p95 latency cutoffs, "bursty" definition).
- **Phase 8**: virtualization performance-impact percentages per workload class.
- **Phase 6**: behavioral classifier cluster boundaries.
- **Phase 6**: exact v1 signature catalog contents.
- **Phase 9**: PDF rendering path (`chromedp` vs. `wkhtmltopdf`) — decide and justify.
- **Phase 11**: Windows code-signing certificate sourcing.

---

## 10. Critical Recap

Re-read before any phase begins: **zero impact on the host workload**,
**ephemeral with a clean uninstall**, **single static Go binary cross-compiled
for Linux and Windows**, **rule-based deterministic recommender — no LLM at
runtime**, **vendor-neutral output describing characteristics not SKUs**,
**stable versioned JSON schema treated as a public API**, **three-tier
recommendations with confidence scoring**, **virtualization verdict
required**, **multi-workload consolidation-vs-split analysis required**,
**stop at every phase boundary and wait for approval**, and **when in doubt,
ask — do not invent**.
