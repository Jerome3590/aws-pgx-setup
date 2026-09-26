# pgx-analysis EC2 sessions

From-scratch Spot sessions. Same lifecycle as surgical-ed-vr
(`launch_analysis_session.sh` --> job --> `cancel_analysis_session.sh`).
Do not keep a session AMI or a warm 197 GB root. Artifacts live in S3
(`pgxdatalake`, dashboard bucket `jerome-dixon.io`).

Account `535362115856`, profile `mushin` (or `pgx`), region `us-east-1`.
Do not use surgical-ed-vr instance IDs here.

Launch and teardown live in this repo (`aws-pgx-setup`). Analysis jobs
run from the cloned `pgx-analysis` tree.

## Final production workflow (do not deviate)

This is the only supported path. Overlay copies, AL2 pin downgrades,
`resume_python_no_r.sh`, and “pip install the missing module name” are
emergencies, not the runbook.

1. **Push session scripts before launch.** Commit `aws-pgx-setup`, then
   commit the parent submodule pointer on `pgx-analysis` `main`. A shallow
   clone of GitHub will otherwise have an empty `aws-pgx-setup/` and
   `run_ec2_analysis_session.sh` will be missing.
2. **Pick the OS from `requirements.txt`.** Default `OS=al2023`. See
   [`README_os_and_libraries.md`](README_os_and_libraries.md). Do not
   launch AL2 and then downgrade DuckDB/NumPy/pandas.
3. **Launch** with `launch_pgx_session.sh` (`INSTALL_R=0` unless the job
   calls BupaR / `r_helpers`). Git Bash must pass Windows paths to the
   Windows `aws` + Python (`cygpath -w`); do not feed `/c/...` into
   Python `Path`.
4. **If Public IP is empty**, allocate/associate an EIP. Hold
   `sedvr-idle-stop-<id>` during bootstrap.
5. **Wait** for SES “Bootstrap Completed” (or
   `python3.11 -c "import duckdb,pandas,boto3,pyarrow"`).
6. **Clone + deps:** `clone_and_setup_pgx.sh` (recurse-submodules +
   `pip install -r requirements.txt` even if `jupyter-env` already exists).
   `preflight_pgx_python.sh` must print `pgx-imports-ok`. That check
   covers `py_helpers.common_imports` (`mlxtend`) and `aws_utils`
   (`psutil`).
7. **Run** with `run_ec2_analysis_session.sh --job-name "..." -- <cmd>`.
8. **Teardown order:** SES COMPLETE → cancel the **persistent** Spot
   request → terminate → delete idle alarm → SES FINAL. Cancel the
   request first or the box comes back.

Gold-cohort extracts and DTW bin transitions do **not** need
`model_events` or R. One band: `x2iedn.2xlarge` (256 GiB), not 1 TB.

## Lifecycle

```text
Push aws-pgx-setup + parent submodule pointer
  --> AL2023 AMI (chosen for requirements.txt) --> launch_pgx_session.sh
  --> EIP if no public IP; hold sedvr-idle-stop-<id>
  --> wait for Python 3.11 / SES "bootstrap" mail
  --> clone_and_setup_pgx.sh  (recurse-submodules + pip -r requirements.txt)
  --> preflight_pgx_python.sh  (mlxtend, psutil, duckdb, s3_utils)
  --> run_ec2_analysis_session.sh --job-name "..." -- <cmd>
  --> SES COMPLETE (summary)
  --> cancel Spot request --> terminate --> delete idle alarm
  --> SES FINAL (shutdown confirmed)
```

A leftover **persistent** Spot request will revive the box. Always cancel
the request, then terminate.

## Errors already paid for (do not repeat)

Confirmed 2026-09-26 on `i-07d95a421d09f5bff` (AL2) and
`i-0bdc2808cbf4b09f5` (AL2023):

| What happened | Production rule |
|---------------|-----------------|
| AL2 + `numpy>=2` / `duckdb>=1.4` `httpfs` | Launch AL2023. Never pin `duckdb==1.1.3` or NumPy 1.26 on a new box. |
| `INSTALL_R=1` compiled R; `bupaverse` without `repos=` + missing `libuv-devel` (`uv.h`) killed cloud-init with `set -e` **before Python** | Default `INSTALL_R=0`. R only if the job calls R. Always `repos=` and `libuv-devel`. |
| `git clone --depth 1` without `--recurse-submodules` | `clone_and_setup_pgx.sh` inits `aws-pgx-setup`. Preflight fails if session scripts are missing. |
| Waiter skipped `pip -r` because `jupyter-env` already existed; `common_imports` then raised `ModuleNotFoundError: mlxtend`; SES notify needed `psutil` | `requirements.txt` includes `mlxtend` and `psutil`. Always `pip -r` after activate. Preflight before the job. |
| Waiter then installed `duckdb==1.1.3` on AL2023 | That fallback is AL2-only and retired for new sessions. |
| “Install the missing module” pulled PyPI `phases`, shadowing `2_create_cohort/phases` | Install from `requirements.txt` only. |
| Git Bash `/c/...` user-data unread by Windows Python | `launch_pgx_session.sh` uses `cygpath -w` (`USER_DATA_WIN`). |
| Subnet assigned no public IP | Allocate/associate EIP; pass `EIP_ALLOCATION_ID` into cancel. |
| Persistent Spot left active after terminate | `cancel_pgx_session.sh` cancels the request first. |

## Scripts

| Location | Script | Role |
|----------|--------|------|
| this repo | `ec2/scripts/bash/launch_pgx_session.sh` | Launch AL2023 Spot + idle-stop alarm (`OS=al2` legacy) |
| this repo | `ec2/scripts/bash/clone_and_setup_pgx.sh` | Clone `pgx-analysis`, init this submodule, venv |
| this repo | `ec2/scripts/bash/run_ec2_analysis_session.sh` | Run job, SES COMPLETE, then destroy |
| this repo | `ec2/scripts/bash/cancel_pgx_session.sh` | Cancel Spot, SES FINAL, terminate, optional EIP release |
| this repo | `ec2/scripts/python/ec2_session_notify.py` | SES helper (`complete` / `error` / `shutdown`) |
| this repo | `ec2/scripts/bash/preflight_pgx_python.sh` | Fail if submodule empty or `mlxtend`/`psutil`/helpers missing |
| this repo | `ec2/scripts/bash/wait_bootstrap_and_run_65_74.sh` | One-job waiter (AL2023 production path, not an alternate pin set) |
| `pgx-analysis` | `utility_scripts/run_opioid_65_74_cohort_and_transitions.sh` | One-band gold cohorts + DTW transitions |

User-data: `ec2/bootstrap/ec2_al2023_session.sh` (default) plus
`ec2/bootstrap/install_r_rstudio.sh` (written to
`/usr/local/sbin/install_r_rstudio.sh` on first boot). AL2 bootstrap is
legacy only.

After clone, project root is `/home/pgx3874/pgx-analysis` and the
interpreter is `~/jupyter-env/bin/python`.

## R / RStudio (opt-in)

Default is **Python/DuckDB only** (`INSTALL_R=0`). Do not compile R unless
the job actually calls R scripts (BupaR, `r_helpers`, or `Rscript`).

```bash
# Launch with R because this session will run BupaR
INSTALL_R=1 AWS_PROFILE=mushin AMI_ID="$AMI_ID" \
  INSTANCE_TYPE=x2iedn.2xlarge bash ec2/scripts/bash/launch_pgx_session.sh

# Already running, discovered you need R:
sudo bash /usr/local/sbin/install_r_rstudio.sh
```

Gold-cohort extracts, DTW / bin transitions, SHAP, and FFA stay on the
default path. Compiling R is most of a 1–2 hour first boot; skip it when
the job is Python.

### Known R package failures (2026-09-26, `i-07d95a421d09f5bff`)

`ec2_linux2_single.sh` used to compile R on every boot and then
`set -e` aborted **before Python 3.11**. Two separate issues:

1. **`fs` / `uv.h`:** `install.packages(... rmarkdown ...)` failed to
   compile CRAN `fs` (`fatal error: uv.h: No such file or directory`).
   That blocked `sass` → `bslib` → `rmarkdown`. Install `libuv-devel`
   (EPEL) before R packages. `caret` / `dplyr` / `ggplot2` still installed.
2. **`bupaverse` CRAN mirror:** the next line was
   `install.packages('bupaverse')` with **no `repos=`**. R stopped with
   `Error in contrib.url(repos, type): trying to use CRAN without setting
   a mirror` and cloud-init exited 255. The SES “Install Failed” mail also
   failed (quotes in `$BASH_COMMAND`). Always pass
   `repos="http://cran.rstudio.com"` on every `install.packages` call.

R itself (`4.4.3`) compiled. The 65-74 job does not need R — resume
Python/DuckDB only. `INSTALL_R=0` now skips the inline R block.

Do not stay on AL2 and pin older NumPy/DuckDB. New sessions use AL2023
so `requirements.txt` installs as written
([`README_os_and_libraries.md`](README_os_and_libraries.md)).

## Instance size

Stay on the `x2iedn` family (NVMe + memory per vCPU). Override with
`INSTANCE_TYPE`.

| Job | Type | vCPU | RAM | Notes |
|-----|------|------|-----|--------|
| One band / visuals / gold-cohort extract | `x2iedn.2xlarge` | 8 | 256 GiB | Surgical-ed-vr default. Enough for `opioid_ed` 65-74 cohorts + bin transitions |
| Heavier one-band rebuild (medical+pharmacy + DuckDB headroom) | `x2iedn.4xlarge` | 16 | 512 GiB | Optional |
| Full multi-band pipeline | `x2iedn.8xlarge` | 32 | 1024 GiB | Launcher default |

Bin transitions need person-year event counts, not `model_events`. Prefer
`gold/cohorts/.../cohort.parquet`, then DTW filter, then `model_events`.

## Launch

From `aws-pgx-setup` (Git Bash). Windows `aws` + profile `mushin`
must be visible; if SSM returns `AMI None`, pass `AMI_ID` explicitly.

```bash
# Targeted job (256 GiB) -- AL2023 so current requirements.txt fits
AWS_PROFILE=mushin INSTANCE_TYPE=x2iedn.2xlarge \
  INSTANCE_NAME=pgx-analysis-session \
  bash ec2/scripts/bash/launch_pgx_session.sh
# INSTALL_R=0 by default. Add INSTALL_R=1 only when the job calls R.

# Full pipeline (1 TB)
AWS_PROFILE=mushin bash ec2/scripts/bash/launch_pgx_session.sh
```

Defaults: subnet `subnet-5de81a53` (us-east-1f), SG `sg-0eb0da772c42415dd`,
key `mushin_pgx`, instance profile `EC2_Spot`, root 80 GB gp3
`DeleteOnTermination=true`. Other-AZ Spot:
`SUBNET_ID=subnet-5bfc3416` (us-east-1a). On-demand last resort.

The subnet may not assign a public IP. If `Public IP: <none>`, allocate and
associate an Elastic IP (free while the instance is running). Pass
`EIP_ALLOCATION_ID=eipalloc-...` into cancel so teardown releases it.

```bash
aws ec2 allocate-address --profile mushin --region us-east-1 --domain vpc \
  --tag-specifications 'ResourceType=elastic-ip,Tags=[{Key=Project,Value=pgx-analysis}]'
aws ec2 associate-address --profile mushin --region us-east-1 \
  --instance-id i-xxxxxxxx --allocation-id eipalloc-xxxxxxxx --allow-reassociation
```

Hold the idle-stop alarm during bootstrap (CPU can drop between compile
steps and the 45-minute `sedvr-idle-stop-<id>` alarm will stop the box):

```bash
aws cloudwatch disable-alarm-actions --profile mushin \
  --alarm-names sedvr-idle-stop-i-xxxxxxxx
```

## SSH

Key: `/c/Projects/mushin_pgx.pem` (Git Bash) or `/mnt/c/Projects/mushin_pgx.pem`
(WSL). Copy to a Linux temp file and `chmod 600` before ssh (DrvFs reports
`0444` and OpenSSH ignores the key).

AL2023 accepts `ec2-user` immediately. `pgx3874` exists only after
bootstrap creates it (or you clone under `ec2-user`). Try `ec2-user` first.

```bash
K=$(mktemp); cp /c/Projects/mushin_pgx.pem "$K"; chmod 600 "$K"
ssh -i "$K" -o StrictHostKeyChecking=accept-new ec2-user@<public-ip>
```

Wait until `python3.11 -c "import duckdb,pandas,boto3,pyarrow"` works
(bootstrap SES mail, often ~1 hour; longer only if `INSTALL_R=1`). Then
**only** `clone_and_setup_pgx.sh` (it inits the submodule, `pip -r`, and
preflight). Do not `git clone --depth 1` without `--recurse-submodules`.

```bash
bash /path/to/aws-pgx-setup/ec2/scripts/bash/clone_and_setup_pgx.sh
```

## Run a job (email + destroy)

On the box, after clone:

```bash
export PGX_DATA_ROOT=/mnt/nvme
# Mount unused NVMe if /mnt/nvme is empty (see setup_mnt_drive.sh).

cd ~/pgx-analysis
bash aws-pgx-setup/ec2/scripts/bash/run_ec2_analysis_session.sh \
  --job-name "opioid_ed 65-74 gold cohorts + bin transitions" -- \
  bash utility_scripts/run_opioid_65_74_cohort_and_transitions.sh
```

`KEEP_ALIVE=1` skips destroy. Failed jobs leave the instance up unless
`--shutdown-on-error`.

Teardown only (laptop or box):

```bash
AWS_PROFILE=mushin INSTANCE_ID=i-xxxxxxxx \
  EIP_ALLOCATION_ID=eipalloc-xxxxxxxx \
  bash ec2/scripts/bash/cancel_pgx_session.sh
```

Order: cancel Spot request --> delete `sedvr-idle-stop-<id>` --> SES FINAL
--> terminate --> release EIP if `EIP_ALLOCATION_ID` is set.

Idle hold: disable that alarm's actions. Failover: other-AZ Spot, then
on-demand last resort.

## SES

From `jerome@mushinsolutions.com` to `dixonrj@vcu.edu`
(`py_helpers.aws_utils.send_status_email_ses`).

| Subject | When |
|---------|------|
| `[pgx-analysis-session] COMPLETE: <job>` | Job exit 0; short summary (elapsed, commit, last log lines) |
| `[pgx-analysis-session] FINAL: EC2 shutdown confirmed` | Spot cancelled; terminate about to run |
| `[pgx-analysis-session] ERROR: <job>` | Job failed; instance left running |

Bootstrap still sends its own SES mail (script started / Python installed /
bootstrap completed).
