#!/usr/bin/env bash
#
# phase0-finalize.sh — finish Phase 0 of Crucible:
#   1. Fetch BSL 1.1 template (with fallback) and render LICENSE
#   2. Copy Additional Use Grant byte-for-byte from LICENSING.md
#   3. Configure git identity from a prompted email
#   4. Install GitHub CLI (gh) via the official apt repo if absent
#   5. Authenticate gh, init/commit the repo, create private
#      github.com/lcweller/crucible, push, watch CI, report result.
#
# Idempotent where it can be; interactive only for the email prompt and
# `gh auth login`. Run from anywhere; it cd's to ~/projects/crucible.

set -euo pipefail

REPO_DIR="${HOME}/projects/crucible"
REPO_SLUG="lcweller/crucible"
PRIMARY_URL="https://raw.githubusercontent.com/mariadb-corporation/bsl/master/TEMPLATE"
FALLBACK_URL="https://mariadb.com/bsl11/"

LICENSOR="Landon Weller"
LICENSED_WORK="Crucible v1.0"
CHANGE_DATE="2030-05-13"
CHANGE_LICENSE="Apache License, Version 2.0"

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31m[fatal]\033[0m %s\n' "$*" >&2; exit 1; }

cd "$REPO_DIR" || die "Cannot cd to $REPO_DIR"
[[ -f LICENSING.md ]] || die "LICENSING.md not found; aborting."
[[ -f CLAUDE.md   ]] || die "CLAUDE.md not found; this doesn't look like the Crucible repo."

# --------------------------------------------------------------------
# 1. Fetch the BSL 1.1 template
# --------------------------------------------------------------------
log "Fetching BSL 1.1 template"

TMP_TEMPLATE="$(mktemp)"
trap 'rm -f "$TMP_TEMPLATE"' EXIT

fetch() {
  local url="$1" out="$2"
  curl --fail --silent --show-error --location \
       --max-time 30 --retry 2 \
       "$url" -o "$out"
}

if fetch "$PRIMARY_URL" "$TMP_TEMPLATE" && [[ -s "$TMP_TEMPLATE" ]]; then
  echo "    fetched from primary: $PRIMARY_URL"
else
  warn "primary URL failed; trying fallback"
  if fetch "$FALLBACK_URL" "$TMP_TEMPLATE" && [[ -s "$TMP_TEMPLATE" ]]; then
    echo "    fetched from fallback: $FALLBACK_URL"
    # The fallback is an HTML page; if so, scrape the <pre> block that
    # contains the actual license text. If no <pre>, leave as-is and hope
    # the sed substitutions below still bite.
    if grep -qi '<pre' "$TMP_TEMPLATE"; then
      python3 - "$TMP_TEMPLATE" <<'PY'
import re, sys, html
src = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search(r"<pre[^>]*>(.*?)</pre>", src, flags=re.S | re.I)
if m:
    text = html.unescape(re.sub(r"<[^>]+>", "", m.group(1)))
    open(sys.argv[1], "w", encoding="utf-8").write(text.strip() + "\n")
PY
    fi
  else
    die "Could not fetch BSL 1.1 template from either URL. Check connectivity and rerun."
  fi
fi

[[ -s "$TMP_TEMPLATE" ]] || die "BSL template is empty after fetch."

# --------------------------------------------------------------------
# 2. Extract Additional Use Grant byte-for-byte from LICENSING.md
# --------------------------------------------------------------------
log "Extracting Additional Use Grant from LICENSING.md"

# Pull every line that begins with '> ' inside the
# '## The Additional Use Grant' section, strip the leading '> ',
# preserve newlines exactly as written.
AUG_FILE="$(mktemp)"
trap 'rm -f "$TMP_TEMPLATE" "$AUG_FILE"' EXIT

awk '
  /^## The Additional Use Grant/ { in_section = 1; next }
  in_section && /^## /           { in_section = 0 }
  in_section && /^> /            { sub(/^> /, ""); print }
' LICENSING.md > "$AUG_FILE"

[[ -s "$AUG_FILE" ]] || die "No Additional Use Grant block found under '## The Additional Use Grant' in LICENSING.md"

echo "    extracted Additional Use Grant:"
sed 's/^/      | /' "$AUG_FILE"

# --------------------------------------------------------------------
# 3. Render LICENSE: copy template, substitute the five fields
# --------------------------------------------------------------------
log "Rendering LICENSE"

cp "$TMP_TEMPLATE" LICENSE

# Python handles multi-line Additional Use Grant cleanly and tolerates
# whichever placeholder style the template ships with.
python3 - "$AUG_FILE" <<PY
import re, sys, pathlib

aug = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").rstrip("\n")
license_path = pathlib.Path("LICENSE")
text = license_path.read_text(encoding="utf-8")

def sub_field(name, value, body):
    # Match "<name>:" followed by anything to end of line (any placeholder).
    pat = re.compile(r'^(' + re.escape(name) + r':)[ \t]*.*$', re.MULTILINE)
    if pat.search(body):
        return pat.sub(lambda m: m.group(1) + ' ' + value, body, count=1)
    # If the template doesn't have a labelled line, prepend the field so the
    # output is still complete and machine-parseable.
    return f"{name}: {value}\n" + body

# Single-line fields
text = sub_field("Licensor",       "${LICENSOR}",       text)
text = sub_field("Licensed Work",  "${LICENSED_WORK}",  text)
text = sub_field("Change Date",    "${CHANGE_DATE}",    text)
text = sub_field("Change License", "${CHANGE_LICENSE}", text)

# Additional Use Grant: keep the placeholder line as the label, then the
# full multi-line grant on the following lines, indented for readability.
indent = "  "
aug_block = "\n".join(indent + line if line else "" for line in aug.splitlines())
pat = re.compile(r'^(Additional Use Grant:)[ \t]*.*$', re.MULTILINE)
if pat.search(text):
    text = pat.sub(lambda m: m.group(1) + "\n" + aug_block, text, count=1)
else:
    text = f"Additional Use Grant:\n{aug_block}\n" + text

license_path.write_text(text, encoding="utf-8")
print("    LICENSE written (" + str(len(text)) + " bytes)")
PY

# --------------------------------------------------------------------
# 4. Git identity
# --------------------------------------------------------------------
log "Configuring git identity"

current_email="$(git config --global --get user.email || true)"
current_name="$(git config --global --get user.name  || true)"

if [[ -n "$current_email" ]]; then
  echo "    git --global user.email already set to: $current_email"
  read -r -p "    Use this email? [Y/n] " keep
  if [[ "${keep,,}" == "n" || "${keep,,}" == "no" ]]; then
    current_email=""
  fi
fi

if [[ -z "$current_email" ]]; then
  read -r -p "    Enter your GitHub email: " gh_email
  [[ -n "$gh_email" ]] || die "Empty email; aborting."
  git config --global user.email "$gh_email"
  echo "    set git --global user.email = $gh_email"
fi

if [[ -z "$current_name" ]]; then
  git config --global user.name "$LICENSOR"
  echo "    set git --global user.name = $LICENSOR (no prior value)"
fi

# --------------------------------------------------------------------
# 5. Ensure gh is installed (official apt repo)
# --------------------------------------------------------------------
log "Ensuring GitHub CLI is installed"

if command -v gh >/dev/null 2>&1; then
  echo "    gh already installed: $(gh --version | head -n1)"
else
  echo "    installing gh from the official apt repository..."
  command -v sudo >/dev/null || die "sudo not available; install gh manually and rerun."
  sudo apt-get update -y
  sudo apt-get install -y curl ca-certificates gnupg
  KEY=/usr/share/keyrings/githubcli-archive-keyring.gpg
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo dd of="$KEY" status=none
  sudo chmod go+r "$KEY"
  arch="$(dpkg --print-architecture)"
  echo "deb [arch=$arch signed-by=$KEY] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update -y
  sudo apt-get install -y gh
  command -v gh >/dev/null || die "gh install reported success but binary not on PATH"
  echo "    gh installed: $(gh --version | head -n1)"
fi

# --------------------------------------------------------------------
# 6. gh auth login
# --------------------------------------------------------------------
log "Authenticating gh"

if gh auth status >/dev/null 2>&1; then
  echo "    gh is already authenticated"
else
  gh auth login
fi

# --------------------------------------------------------------------
# 7. Initialize repo, commit, create remote, push
# --------------------------------------------------------------------
log "Initializing git repository"

git init -q
git symbolic-ref HEAD refs/heads/main 2>/dev/null || git checkout -q -B main

git add -A
if git diff --cached --quiet; then
  echo "    no staged changes; assuming an earlier commit covers Phase 0"
else
  git commit -q -m "$(cat <<'MSG'
chore(phase-0): scaffold Crucible repository

- Module layout (cmd/, internal/, pkg/schema/, signatures/, rules/v1/, docs/)
- CLI smoke test (cobra root command + stubs)
- BSL 1.1 LICENSE, LICENSING.md, LICENSE-HEADER.txt
- Makefile, .golangci.yml, .gitignore
- GitHub Actions CI matrix (lint/vet/test/race/cross-compile/govulncheck)
- README.md skeleton and docs/architecture.md

Phase 0 of the build plan in CLAUDE.md.
MSG
)"
  echo "    committed: $(git rev-parse --short HEAD)"
fi

log "Creating remote $REPO_SLUG (private) and pushing"

if gh repo view "$REPO_SLUG" >/dev/null 2>&1; then
  echo "    remote $REPO_SLUG already exists; reusing"
  if ! git remote get-url origin >/dev/null 2>&1; then
    git remote add origin "https://github.com/${REPO_SLUG}.git"
  fi
  git push -u origin main
else
  gh repo create "$REPO_SLUG" --private --source=. --remote=origin --push
fi

# --------------------------------------------------------------------
# 8. Watch CI and report
# --------------------------------------------------------------------
log "Watching CI run"

# Give Actions a few seconds to register the workflow run.
sleep 5

# Find the most recent run id on the just-pushed commit; fall back to
# whatever 'gh run list' reports first.
RUN_ID=""
for _ in 1 2 3 4 5; do
  RUN_ID="$(gh run list --branch main --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)"
  [[ -n "$RUN_ID" && "$RUN_ID" != "null" ]] && break
  sleep 3
done

if [[ -z "$RUN_ID" || "$RUN_ID" == "null" ]]; then
  warn "no workflow run found yet; run 'gh run watch' manually once Actions catches up."
  exit 0
fi

echo "    watching run $RUN_ID"
set +e
gh run watch "$RUN_ID" --exit-status
ci_status=$?
set -e

echo
if (( ci_status == 0 )); then
  printf '\033[1;32m=== CI PASSED ===\033[0m\n'
  gh run view "$RUN_ID" --log-failed >/dev/null 2>&1 || true
else
  printf '\033[1;31m=== CI FAILED (exit %d) ===\033[0m\n' "$ci_status"
  echo "Failing logs:"
  gh run view "$RUN_ID" --log-failed || true
fi

echo
echo "Repository:  https://github.com/${REPO_SLUG}"
echo "CI run:      $(gh run view "$RUN_ID" --json url --jq .url 2>/dev/null || echo 'unknown')"
exit "$ci_status"
