---
name: verifying-claude-source
description: Verifies that the Dockerfile uses the current official Claude Code GCS bucket URL by comparing against the install script at https://claude.ai/install.sh. Use when Docker builds fail, before production deployments, when updating containers, or when the user mentions "GCS bucket", "Claude Code source", "install URL", or "Dockerfile verification".
---

# Verifying Claude Code Source URL

## Quick start

Verify the Dockerfile uses the correct Claude Code download URL:

```bash
.claude/skills/update-claude-source/scripts/verify-source.sh
```

**Expected output:**
- ✅ **"Dockerfile is up to date"** - GCS bucket URL matches official source, no action needed
- ⚠️ **"Dockerfile URL differs from official source"** - Update required (see workflow below)

The script compares the `GCS_BUCKET` variable in the Dockerfile against the authoritative source at `https://claude.ai/install.sh`.

## Update workflow with checklist

If verification fails, copy this checklist and track your progress:

```
- [ ] Step 1: Run auto-update
- [ ] Step 2: Review changes
- [ ] Step 3: Test build
- [ ] Step 4: Verify installation
- [ ] Step 5: Commit changes
```

**Step 1: Run auto-update**
```bash
.claude/skills/update-claude-source/scripts/verify-source.sh --update
```

**Step 2: Review changes**
```bash
git diff Dockerfile
```
Verify only the `GCS_BUCKET` URL changed (line ~11).

**Step 3: Test build**
```bash
docker compose build --no-cache
```
Build should complete without errors.

**Step 4: Verify installation**
```bash
docker compose run --rm claude --version
```
Should display Claude Code version (e.g., `2.1.17`).

**Step 5: Commit changes**
```bash
git add Dockerfile
git commit -m "Update Claude Code GCS bucket URL"
```

## Manual verification

If the script is unavailable, extract and compare URLs manually:

```bash
# Extract official GCS bucket URL
curl -fsSL https://claude.ai/install.sh | grep 'GCS_BUCKET=' | cut -d'"' -f2

# Extract Dockerfile GCS bucket URL
grep 'GCS_BUCKET=' Dockerfile | cut -d'"' -f2

# Test official bucket accessibility
OFFICIAL_URL="<paste-url-from-first-command>"
curl -fsSL "${OFFICIAL_URL}/latest"
```

**Expected result:** Version string like `2.1.17`

**If URLs differ:** Manually update the `GCS_BUCKET` line in the Dockerfile to match the official URL, then follow steps 2-5 in the workflow above.

## Why this verification matters

The Claude Code GCS bucket URL contains a UUID that identifies Anthropic's distribution infrastructure:

```
https://storage.googleapis.com/claude-code-dist-<UUID>/claude-code-releases
```

**Failure modes if URL is outdated:**
- Docker build fails with "404 Not Found"
- Binary download returns empty or error files
- Container runs but Claude Code is missing

The install script at `https://claude.ai/install.sh` is the authoritative source. This skill ensures the Dockerfile stays synchronized.

## Script reference

**Script location:** [scripts/verify-source.sh](scripts/verify-source.sh)

**Usage:**
```bash
# Verification only (exit 0 if match, exit 1 if mismatch)
./scripts/verify-source.sh

# Auto-update Dockerfile if URLs differ
./scripts/verify-source.sh --update
```

**What the script does:**
1. Fetches https://claude.ai/install.sh
2. Extracts `GCS_BUCKET` variable using grep and cut
3. Tests bucket accessibility by fetching `/latest` endpoint
4. Compares with Dockerfile's `GCS_BUCKET` value
5. Optionally updates Dockerfile with `--update` flag
6. Returns colored status output

## Related files

- [Dockerfile](../../Dockerfile) (line ~11) - Contains `GCS_BUCKET` URL
- [scripts/verify-source.sh](scripts/verify-source.sh) - Bundled verification script
- [CLAUDE.md](../../CLAUDE.md) - Project documentation including GCS bucket discovery process
