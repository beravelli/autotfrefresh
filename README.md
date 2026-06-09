# autotfrefresh

GitOps-based IaC refresh system using **OpenTofu**, **Terragrunt**, and **Jenkins**.  
Pushing a version tag to this monorepo automatically validates the changed module, finds every live stack that depends on it, plans the changes, and waits for a manual approval before applying.

---

## Architecture

```
git push origin vpc/v1.0.1
        │
        ▼
┌──────────────────────────────┐
│  module-tag-pipeline         │  Multibranch Pipeline
│  (Jenkinsfile)               │  • detects tag pattern <module>/v<semver>
│                              │  • validates modules/<name>/ with tofu validate
│                              │  └─▶ triggers refresh-pipeline (wait: false)
└──────────────────────────────┘
        │
        ▼
┌──────────────────────────────┐
│  refresh-pipeline            │  Parameterized Pipeline
│  (Jenkinsfile.refresh)       │  • find_affected_stacks.sh → grep live/ for module ref
│                              │  • tofu validate (DRY_RUN) or terragrunt plan (real)
│                              │  • manual approval gate (24 h timeout)
│                              │  └─▶ terragrunt apply each stack sequentially
└──────────────────────────────┘

        (daily cron, 08:00 UTC)
        │
        ▼
┌──────────────────────────────┐
│  drift-check                 │  Scheduled Pipeline
│  (Jenkinsfile.check)         │  • check_module_versions.sh
│                              │  • git ls-remote → latest tag per module
│                              │  • compares live/ refs vs latest tags
│                              │  • UNSTABLE + warning if any stack is behind
└──────────────────────────────┘
```

### Toolchain

| Tool | Version | Location |
|------|---------|----------|
| OpenTofu | 1.7.3 | `/var/jenkins_home/bin/tofu` |
| Terragrunt | 0.67.16 | `/var/jenkins_home/bin/terragrunt` |
| Jenkins | 2.555.2 | `http://localhost:8080` (K8s, docker-desktop) |

---

## Repository Layout

```
autotfrefresh/
├── Jenkinsfile                     # Module tag trigger pipeline
├── Jenkinsfile.refresh             # Live-infra refresh pipeline
├── Jenkinsfile.check               # Scheduled version drift check
├── terragrunt.hcl                  # Root config (local backend for testing)
│
├── modules/
│   ├── vpc/                        # Full VPC module (terraform-aws-modules/vpc)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── eks/                        # EKS module stub (validates cleanly)
│   │   ├── main.tf
│   │   └── variables.tf
│   └── rds/                        # RDS module stub (validates cleanly)
│       ├── main.tf
│       └── variables.tf
│
├── live/
│   ├── dev/us-east-1/
│   │   ├── env.hcl                 # account_id = 111122223333
│   │   ├── vpc/terragrunt.hcl      # source = git::…//modules/vpc?ref=vpc/v1.0.0
│   │   ├── eks/terragrunt.hcl
│   │   └── rds/terragrunt.hcl
│   └── prod/us-east-1/
│       ├── env.hcl                 # account_id = 444455556666
│       ├── vpc/terragrunt.hcl
│       ├── eks/terragrunt.hcl
│       └── rds/terragrunt.hcl
│
└── scripts/
    ├── find_affected_stacks.sh     # Scans live/ for stacks using the updated module
    ├── tofu_plan.sh                # Patches ref, runs validate (DRY_RUN) or plan
    ├── tofu_apply.sh               # Runs terragrunt apply with saved plan file
    └── check_module_versions.sh    # Compares live/ refs vs latest tags (drift check)
```

---

## Tag Convention

Tags follow the format `<module>/v<semver>`:

```
vpc/v1.0.0    eks/v1.0.0    rds/v1.0.0
vpc/v1.0.1    eks/v2.1.0    rds/v1.1.0
```

The Jenkins multibranch pipeline parses the tag with the regex `^([a-z0-9_\-]+)\/v(\d+\.\d+\.\d+.*)$` to extract `MODULE_NAME` and `MODULE_VERSION` automatically — no hardcoding required.

---

## Pipeline Details

### `Jenkinsfile` — Module Tag Trigger

Runs on every tag that matches `<module>/v<semver>`.

**Stages:**

1. **Parse tag** — extracts `MODULE_NAME` and `MODULE_VERSION` from `TAG_NAME`
2. **Validate module** — runs `tofu init -backend=false && tofu validate && tofu fmt -check` inside `modules/<name>/`
3. **Trigger refresh** — fires `gitops/refresh-pipeline` downstream (`wait: false`) with:
   - `MODULE_NAME`, `MODULE_VERSION`, `MODULE_REPO_URL`
   - `DRY_RUN=true` (default; override manually for real runs)

Validation failure **blocks** the downstream trigger — broken modules never reach live infra.

---

### `Jenkinsfile.refresh` — Live-Infra Refresh

Parameterized pipeline that applies module version bumps across all affected stacks.

**Parameters:**

| Parameter | Default | Description |
|-----------|---------|-------------|
| `MODULE_NAME` | _(required)_ | e.g. `vpc` |
| `MODULE_VERSION` | _(required)_ | e.g. `v1.0.1` |
| `MODULE_REPO_URL` | this repo | Git URL of the module monorepo |
| `TRIGGERED_BY` | `manual` | Free-text provenance label |
| `DRY_RUN` | `true` | `true` = validate only, no AWS creds needed |
| `AUTO_APPROVE` | `false` | Skip approval gate (CI use only) |
| `ENV_FILTER` | _(empty)_ | Restrict to `dev` or `prod` (empty = all) |

**Stages:**

1. **Validate inputs** — guards against missing required params
2. **Find affected stacks** — `scripts/find_affected_stacks.sh` greps `live/` for `git::…//modules/<name>` and returns only stacks referencing *this specific module*, not the whole monorepo
3. **Plan / Validate stacks** — for each affected stack:
   - `DRY_RUN=true`: patches the `ref=` in `terragrunt.hcl`, runs `tofu init -backend=false && tofu validate`, then restores the original file
   - `DRY_RUN=false`: full `terragrunt plan -detailed-exitcode` with AWS credentials (`aws-credentials` Jenkins credential)
   - Plan logs archived as build artifacts
4. **Approval gate** — 24-hour `input` step showing the affected stack list; skipped if `AUTO_APPROVE=true`
5. **Apply stacks** — sequential `terragrunt apply` per stack (or dry-run summary)

---

## Version Drift Check

`Jenkinsfile.check` runs `scripts/check_module_versions.sh` daily (and on demand) to warn you when live stacks are pinned to an old module version.

### How it works

1. Scans every `terragrunt.hcl` under `live/` and extracts the current `ref=` for each stack.
2. Calls `git ls-remote --tags` against the upstream repo to find the highest semver tag for each module (one network call per unique module name, cached).
3. Compares `current` vs `latest` and prints a table:

```
Stack                                  Module   Current    Latest     Status
────────────────────────────────────── ──────── ────────── ────────── ──────────────
dev/us-east-1/eks                      eks      v1.0.0     v1.0.0     ✓ up to date
dev/us-east-1/rds                      rds      v1.0.0     v1.0.0     ✓ up to date
dev/us-east-1/vpc                      vpc      v1.0.0     v1.0.1     ⚠  BEHIND
prod/us-east-1/eks                     eks      v1.0.0     v1.0.0     ✓ up to date
prod/us-east-1/rds                     rds      v1.0.0     v1.0.0     ✓ up to date
prod/us-east-1/vpc                     vpc      v1.0.0     v1.0.1     ⚠  BEHIND

⚠  2/6 stack(s) are behind the latest module tags.
```

4. Sets the Jenkins build to **UNSTABLE** if any stack is behind, with a description like `⚠ 2 stack(s) behind latest module tags — see log`.
5. Prints the command to run the refresh pipeline to close the gap.

### Running locally

```bash
# Check all envs
bash scripts/check_module_versions.sh

# Check only prod
bash scripts/check_module_versions.sh https://github.com/beravelli/autotfrefresh.git prod

# Exit code = number of stale stacks (0 = clean, can be used in CI gates)
echo "Stale stacks: $?"
```

### Closing the gap

When the drift-check reports stale stacks, trigger the refresh pipeline for the module:

```
gitops/refresh-pipeline
  MODULE_NAME    = vpc
  MODULE_VERSION = v1.0.1   ← the "Latest" value from the drift report
  DRY_RUN        = true     ← preview first
```

---

## Scripts

### `scripts/find_affected_stacks.sh`

```
Usage: find_affected_stacks.sh <module_repo_url> <module_name> [env_filter]
```

Scans every `terragrunt.hcl` under `live/` for the string:

```
git::<module_repo_url>//modules/<module_name>
```

This narrows the match to the specific module subdirectory, preventing false positives in a monorepo where multiple modules share the same repo URL.

---

### `scripts/tofu_plan.sh`

```
Usage: tofu_plan.sh <stack_path> <repo_url> <module_name> <version> <plan_file> <dry_run>
```

1. **Backs up** `terragrunt.hcl`
2. **Patches** the `ref=` query parameter to the new version using `perl -i -pe`
3. Runs `tofu validate` (DRY_RUN) or `terragrunt plan` (real)
4. **Restores** the original file on exit via `trap cleanup EXIT`

Exit codes follow `terraform plan` semantics: `0` = no changes, `2` = changes detected, `1+` = error.

---

### `scripts/tofu_apply.sh`

```
Usage: tofu_apply.sh <stack_path> <plan_file>
```

Runs `terragrunt apply --terragrunt-non-interactive <plan_file>` from the stack directory.

---

### `scripts/check_module_versions.sh`

```
Usage: check_module_versions.sh [module_repo_url] [env_filter]
```

For each `terragrunt.hcl` in `live/`:
1. Parses the `source = "git::…?ref=<module>/<version>"` line to extract module name and pinned version.
2. Calls `git ls-remote --tags <repo> refs/tags/<module>/v*`, sorts by semver (`sort -V`), and takes the highest.
3. Tags per unique module name are cached in a temp dir — only one network call per module regardless of how many stacks use it.

Exit code equals the number of stale stacks (0 = all up to date). Works on Bash 3 (macOS) and Bash 4+ (Linux / Jenkins).

---

## Backend

The root `terragrunt.hcl` uses a **local** backend for testing — no S3 bucket or DynamoDB table required:

```hcl
remote_state {
  backend = "local"
  config  = {
    path = "${get_repo_root()}/.terraform-state/${path_relative_to_include()}/terraform.tfstate"
  }
}
```

For production, swap to:

```hcl
remote_state {
  backend = "s3"
  config  = {
    bucket         = "my-tfstate-bucket"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}
```

---

## Jenkins Setup

### Jenkins Jobs

| Job | Type | Script path | Trigger |
|-----|------|-------------|---------|
| `gitops/module-tag-pipeline` | Multibranch Pipeline | `Jenkinsfile` | Tag push |
| `gitops/refresh-pipeline` | Pipeline | `Jenkinsfile.refresh` | Downstream / manual |
| `gitops/drift-check` | Pipeline | `Jenkinsfile.check` | Daily cron 08:00 UTC / manual |

**module-tag-pipeline** config highlights:
- SCM: `GitHubSCMSource` pointing at `beravelli/autotfrefresh`
- Discovers **tags only** (`TagDiscoveryTrait`; `BranchDiscoveryTrait` removed)
- `<apiRateLimitChecker>NoThrottle</apiRateLimitChecker>` to bypass Jenkins' GitHub API budget throttle
- Periodic scan every 2 minutes

### Jenkins Node Requirements

The built-in node needs the label `tofu` (or `tofu built-in`) and the following binaries in `PATH`:

```
/var/jenkins_home/bin/tofu        # OpenTofu 1.7.3 arm64 static binary
/var/jenkins_home/bin/terragrunt  # Terragrunt v0.67.16 arm64 static binary
```

Set globally via `Manage Jenkins → System → Global properties → Environment variables`:

```
PATH = /var/jenkins_home/bin:/usr/local/bin:/usr/bin:/bin
```

### Script Approval

The pipeline uses `groovy.json.JsonOutput.toJson` which requires one-time approval in  
**Manage Jenkins → In-process Script Approval**:

```
staticMethod groovy.json.JsonOutput toJson java.lang.Object
```

---

## Quickstart — End-to-End Test

### Prerequisites

- Jenkins running at `http://localhost:8080` (see setup above)
- Both pipeline jobs created and scanned
- Repo cloned locally with SSH key configured for push

### 1. Push a new module version tag

```bash
cd /path/to/autotfrefresh
git tag vpc/v1.0.2
git push origin vpc/v1.0.2
```

### 2. Watch the tag pipeline

Jenkins detects the tag within 2 minutes (or trigger **Scan Repository Now** manually).

`gitops/module-tag-pipeline/vpc%2Fv1.0.2` runs:
- Parses tag → `MODULE_NAME=vpc MODULE_VERSION=v1.0.2`
- Validates `modules/vpc/` → `✓ Success! The configuration is valid.`
- Triggers `gitops/refresh-pipeline`

### 3. Watch the refresh pipeline

`gitops/refresh-pipeline` build runs:
- Finds affected stacks: `prod/us-east-1/vpc`, `dev/us-east-1/vpc`
- Validates both stacks in DRY_RUN mode
- Pauses at the **Approval** gate

### 4. Approve

Click **Apply ✓** in the Jenkins build UI (or via API):

```bash
INPUT_ID=$(curl -s -u admin:admin123 \
  'http://localhost:8080/job/gitops/job/refresh-pipeline/lastBuild/wfapi/pendingInputActions' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['id'])")

CRUMB=$(curl -s -u admin:admin123 -c /tmp/jar.txt \
  'http://localhost:8080/crumbIssuer/api/json' \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['crumbRequestField']+':'+d['crumb'])")

curl -s -u admin:admin123 -b /tmp/jar.txt \
  -H "$CRUMB" -X POST \
  "http://localhost:8080/job/gitops/job/refresh-pipeline/lastBuild/input/${INPUT_ID}/proceedEmpty"
```

### 5. Observe result

```
DRY-RUN mode: skipping real apply. Stacks validated successfully.
  ✓ (would apply) prod/us-east-1/vpc
  ✓ (would apply) dev/us-east-1/vpc
Finished: SUCCESS
```

---

## Moving to Real AWS

1. Add AWS credentials to Jenkins with ID `aws-credentials` (type: *AWS Credentials*)
2. Trigger `gitops/refresh-pipeline` with `DRY_RUN=false`
3. Switch `terragrunt.hcl` root config to the S3 backend (see [Backend](#backend) above)
4. Update `live/*/terragrunt.hcl` `source` refs to point to the desired initial versions

---

## Known Limitations / Notes

- **`tofu fmt -check`** in the tag pipeline is non-fatal — it prints a warning but does not block the flow.
- **GitHub commit status** updates fail without a GitHub token credential (non-fatal; add a PAT with `repo:status` scope to Jenkins as a *Secret text* credential to enable them).
- The `Bad substitution` warning in plan logs is a `/bin/sh` vs `bash` minor issue in the PIPESTATUS capture — validation still passes correctly.
- The `main` branch is not built by the tag pipeline (branch discovery is disabled); only `<module>/v<semver>` tags are scanned.
