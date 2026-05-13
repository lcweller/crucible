# Crucible Licensing

Crucible is licensed under the **Business Source License 1.1** (BSL 1.1) with
an **Additional Use Grant** and a **Change Date** of **2030-05-13**, after
which the license automatically converts to **Apache License 2.0**.

This document is plain-English guidance. The legally controlling text is the
`LICENSE` file at the repository root.

---

## TL;DR

| You are… | May you use Crucible? |
| --- | --- |
| A sysadmin running Crucible on your own (or your employer's) servers to characterize *your own* workloads | **Yes, for free, including commercially.** |
| A consultant running Crucible on a client server during an engagement to deliver a recommendation report to that client | **Yes, for free, including commercially.** |
| A managed service provider, hosting company, or vendor offering "Crucible as a service" — running Crucible *itself* on behalf of paying third parties as a hosted product | **No, not without a commercial license. This is the Additional Use Grant restriction.** |
| A researcher, student, hobbyist, open-source contributor | **Yes, for free.** |
| Anyone, on or after 2030-05-13 | **Yes — the license converts to Apache 2.0 automatically on the Change Date.** |

If you're unsure whether your use is covered, open an issue or contact the
maintainers before deploying at scale.

---

## What BSL 1.1 actually allows

BSL 1.1 is a source-available license. You may:

- **Read** the source code.
- **Modify** it for your own use.
- **Run** it in production on your own infrastructure or on behalf of a single
  customer in a consulting engagement.
- **Redistribute** it, as long as you carry the same license forward and do
  not violate the Additional Use Grant.
- **Self-host** internal copies for internal use.

You may **not**:

- Offer Crucible (or a derivative that performs substantially the same
  function) as a **paid hosted service** to third parties before the Change
  Date. That is the restriction the Additional Use Grant exists to enforce.

The intent is plain: anyone can use Crucible to do their job, including for
money. What you cannot do — until the Change Date — is take Crucible itself
and resell it as somebody else's SaaS.

---

## The Additional Use Grant (verbatim intent)

> You may make production use of the Licensed Work, provided that such use
> does not include offering the Licensed Work to third parties as a hosted or
> managed service whose primary value to the recipient is access to the
> functionality of the Licensed Work itself.

Concrete examples:

- ✅ Acme Corp runs Crucible on their database server and uses the report to
  spec a new server. **Allowed.**
- ✅ A consultant runs Crucible on a client's server, hands the client the
  report, gets paid for the engagement. **Allowed.**
- ✅ A hosting provider runs Crucible internally to right-size the hardware
  they bill customers for. **Allowed.**
- ❌ A hosting provider exposes a "Crucible-as-a-Service" portal where
  customers upload telemetry and receive a Crucible-generated report in
  exchange for a subscription fee. **Not allowed before the Change Date
  without a separate commercial license.**

---

## The Change Date

- **Change Date:** 2030-05-13
- **Change License:** Apache License 2.0

On the Change Date, every version of Crucible released to date under BSL 1.1
automatically becomes available under Apache 2.0. No action by the
maintainers is required. The Additional Use Grant disappears at that point;
all uses, including hosted-service use, become permitted under Apache 2.0
terms.

The Change Date applies per release: a v1.0 binary released today becomes
Apache 2.0 on 2030-05-13. A v2.0 released in 2027 carries its own four-year
Change Date and so on. Each release line ages independently.

---

## License headers in source files

Every Go source file in this repository must carry the SPDX header found in
`LICENSE-HEADER.txt`. CI enforces this. If you contribute a new source file,
copy the header verbatim.

---

## Third-party dependencies

The third-party Go modules Crucible depends on are licensed under their own
terms (mostly Apache 2.0, BSD-3-Clause, and MIT). Their licenses are NOT
overridden by BSL 1.1; they remain in effect for those modules. A
machine-readable SBOM ships with every release tag.

---

## Trademark

"Crucible" as a project name is not licensed under BSL 1.1. You may fork the
code, but you may not call your fork "Crucible" or imply endorsement by the
upstream project. Rename your fork.

---

## Commercial licensing

If your intended use falls outside the Additional Use Grant — most commonly
because you want to offer Crucible as a hosted service — contact the
maintainers to negotiate a commercial license. We are reasonable. We would
rather grant you a paid license than have you fork in a way that fragments
the ecosystem.

---

## Questions

Open an issue tagged `licensing`. We do not give legal advice; we will
clarify intent.
