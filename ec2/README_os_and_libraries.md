# Pick the EC2 OS from the analysis libraries

Do **not** start from an AMI and then downgrade `pgx-analysis/requirements.txt`
to match it. Choose the OS so current pins install as wheels (or compile
with the stock toolchain).

Source of truth for Python pins: `pgx-analysis/requirements.txt`.
Session launch: `ec2/scripts/bash/launch_pgx_session.sh` (`OS=al2023` default).

## Decision

| Job libraries | Required OS floor | Default AMI (SSM) |
|---------------|-------------------|-------------------|
| `duckdb>=1.4` + `httpfs`, `numpy>=2`, `pandas>=3`, `pyarrow>=23`, sklearn/xgboost/catboost | **Amazon Linux 2023** (glibc 2.34, GCC 11, `dnf` Python 3.11) | `/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64` |
| BupaR / `r_helpers` / `Rscript` | Same AL2023 box, then `INSTALL_R=1` (do not pick AL2 just for R) | same + `install_r_rstudio.sh` (dnf path on AL2023) |
| Amazon Linux 2 | **Do not use** for new analysis sessions | — |

`OS=al2` remains only to finish or debug a box that is already AL2.

## Why AL2 fails the current stack

Confirmed on `i-07d95a421d09f5bff` (AL2, GCC 7.3.1, glibc 2.26):

| Pin | What broke |
|-----|------------|
| `numpy>=2` / `pyarrow>=23` | Source build: `NumPy requires GCC >= 9.3`. Wheels are usable only if pip is forced `--only-binary` **and** pins drop to NumPy 1.26 / PyArrow 20. |
| `duckdb>=1.4` `INSTALL httpfs` | Extension needs `GLIBC_2.28`. AL2 has 2.26. Work-around was `duckdb==1.1.3`, which is **below** `requirements.txt`. |
| `pandas>=3` | Follows NumPy 2; same compiler/glibc story. |

Those work-arounds are emergency-only. They are not the analysis environment.

## How to launch

```bash
# Default: AL2023 because requirements.txt needs glibc 2.28+ and GCC 9.3+
AWS_PROFILE=mushin INSTANCE_TYPE=x2iedn.2xlarge \
  bash ec2/scripts/bash/launch_pgx_session.sh

# Same OS; add R only if this job calls BupaR / r_helpers
INSTALL_R=1 AWS_PROFILE=mushin \
  bash ec2/scripts/bash/launch_pgx_session.sh
```

Override only when you must:

```bash
OS=al2 AWS_PROFILE=mushin bash ec2/scripts/bash/launch_pgx_session.sh
```

## Bootstrap pairing

| `OS` | User-data | Python |
|------|-----------|--------|
| `al2023` (default) | `ec2/bootstrap/ec2_al2023_session.sh` | `dnf install python3.11`, then `pip` from current pins |
| `al2` (legacy) | `ec2/bootstrap/ec2_linux2_single.sh` | compile CPython 3.11; **cannot** satisfy current pins |

After clone, `clone_and_setup_pgx.sh` runs `pip install -r requirements.txt`
on that same OS **even if bootstrap already created `~/jupyter-env`**.
`requirements.txt` must include every module `py_helpers.common_imports`
and `aws_utils` import at load time (`mlxtend`, `psutil`, `jinja2`,
`requests`). If that command needs a compiler newer than the AMI, change
the AMI, not the requirements. `preflight_pgx_python.sh` must pass before
any job.

## R / bupaverse (opt-in, same OS)

`INSTALL_R=0` by default. When R is required, stay on AL2023 and install R
there. Known AL2 package bugs (still apply if you compile R anywhere):

1. CRAN `fs` needs `libuv-devel` (`uv.h`). Missing `fs` blocks `sass` →
   `bslib` → `rmarkdown`.
2. Every `install.packages` call must set `repos=` (for example
   `http://cran.rstudio.com`). Bare `install.packages('bupaverse')` aborts
   with `trying to use CRAN without setting a mirror` and, with `set -e`,
   kills cloud-init before Python.

See `README_pgx_session.md` for launch / SES / teardown.
