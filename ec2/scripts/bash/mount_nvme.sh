#!/usr/bin/env bash
# Format (only if no filesystem) and mount unused instance-store NVMe at /mnt/nvme.
# Idempotent if already mounted. Safe as root or as a sudoer (ec2-user).
#
#   bash aws-pgx-setup/ec2/scripts/bash/mount_nvme.sh
#   # shellcheck source=mount_nvme.sh
#   source mount_nvme.sh && mount_nvme_if_needed
#
# Do not format in AL2023 user-data; this helper is the single mount path.
# Env: PGX_NVME_MNT (default /mnt/nvme), PGX_NVME_OWNER (default ec2-user if root,
# otherwise the invoking user).

mount_nvme_if_needed() {
  local mnt="${PGX_NVME_MNT:-/mnt/nvme}"
  local owner="${PGX_NVME_OWNER:-}"
  local dev="" d fstype=""

  if [[ -z "$owner" ]]; then
    if [[ "$(id -u)" -eq 0 ]] && id ec2-user >/dev/null 2>&1; then
      owner="ec2-user"
    else
      owner="$(id -un)"
    fi
  fi

  _nvme_as_root() {
    if [[ "$(id -u)" -eq 0 ]]; then
      "$@"
    else
      sudo "$@"
    fi
  }

  if [[ -d "$mnt" ]] && command -v mountpoint >/dev/null 2>&1 && mountpoint -q "$mnt"; then
    echo "NVMe already mounted at $mnt"
    _nvme_as_root chown -R "$owner:$owner" "$mnt" || true
    return 0
  fi

  if ! _nvme_as_root mkdir -p "$mnt"; then
    echo "WARN: cannot create $mnt (need sudo). Session wrap must not require it." >&2
    return 1
  fi

  for d in /dev/nvme*n1; do
    [[ -b "$d" ]] || continue
    # Never format the root volume (SOURCE is often ${d}p1).
    if findmnt -n -o SOURCE / 2>/dev/null | grep -Fq "$d"; then
      continue
    fi
    if lsblk -no MOUNTPOINT "$d" 2>/dev/null | grep -q '[^[:space:]]'; then
      continue
    fi
    if mount | grep -q "^$d "; then
      continue
    fi
    dev="$d"
    break
  done

  if [[ -z "$dev" ]]; then
    echo "WARN: no unused NVMe device; using $mnt on the current disk"
    _nvme_as_root chown -R "$owner:$owner" "$mnt" || true
    return 0
  fi

  fstype="$(blkid -o value -s TYPE "$dev" 2>/dev/null || true)"
  if [[ -z "$fstype" ]]; then
    echo "Formatting $dev as XFS (no filesystem present)"
    if ! _nvme_as_root mkfs -t xfs "$dev"; then
      echo "WARN: mkfs failed on $dev; using $mnt on the current disk" >&2
      _nvme_as_root chown -R "$owner:$owner" "$mnt" || true
      return 0
    fi
  fi

  if ! _nvme_as_root mount "$dev" "$mnt"; then
    echo "WARN: mount $dev -> $mnt failed; using $mnt on the current disk" >&2
    _nvme_as_root chown -R "$owner:$owner" "$mnt" || true
    return 0
  fi
  _nvme_as_root chown -R "$owner:$owner" "$mnt"
  echo "Mounted $dev at $mnt (owner $owner)"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  mount_nvme_if_needed
fi
