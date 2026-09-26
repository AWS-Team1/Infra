#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  echo "usage: $0 <backup-directory> <bucket> <location> <object-prefix>" >&2
  exit 2
}

BACKUP_DIR=${1:-}
BUCKET=${2:-}
LOCATION=${3:-}
OBJECT_PREFIX=${4:-}

[[ -d "$BACKUP_DIR" && -n "$BUCKET" && -n "$LOCATION" && -n "$OBJECT_PREFIX" ]] || usage
[[ "$BUCKET" =~ ^[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$ ]] || {
  echo "invalid GCS bucket name: $BUCKET" >&2
  exit 2
}
[[ "$OBJECT_PREFIX" != /* && "$OBJECT_PREFIX" != */ && "$OBJECT_PREFIX" != *..* ]] || {
  echo "unsafe GCS object prefix: $OBJECT_PREFIX" >&2
  exit 2
}
[[ -s "$BACKUP_DIR/metadata.json" ]] || { echo "metadata.json is missing or empty" >&2; exit 1; }
[[ -s "$BACKUP_DIR/SHA256SUMS" ]] || { echo "SHA256SUMS is missing or empty" >&2; exit 1; }

(
  cd "$BACKUP_DIR"
  sha256sum --check --strict SHA256SUMS >/dev/null
)

actual_location=$(gcloud storage buckets describe "gs://$BUCKET" --format='value(location)')
[[ "${actual_location^^}" == "${LOCATION^^}" ]] || {
  echo "GCS backup bucket location mismatch: expected $LOCATION, got $actual_location" >&2
  exit 1
}

mapfile -d '' backup_files < <(find "$BACKUP_DIR" -maxdepth 1 -type f -print0 | sort -z)
(( ${#backup_files[@]} > 0 )) || { echo "No backup files found" >&2; exit 1; }

for file in "${backup_files[@]}"; do
  name=$(basename -- "$file")
  object="$OBJECT_PREFIX/$name"
  destination="gs://$BUCKET/$object"
  size=$(stat -c '%s' "$file")
  md5_hash=$(openssl dgst -md5 -binary "$file" | base64 | tr -d '\n')

  # Generation zero is an atomic create-only precondition. A retry can never
  # overwrite an existing live backup object.
  gcloud storage cp \
    "$file" \
    "$destination" \
    --if-generation-match=0 \
    --content-md5="$md5_hash" \
    --quiet

  read -r remote_size remote_md5 < <(
    gcloud storage objects describe \
      "$destination" \
      --format='value(size,md5_hash)'
  )
  [[ "$remote_size" == "$size" && "$remote_md5" == "$md5_hash" ]] || {
    echo "Uploaded GCS object verification failed: $object" >&2
    exit 1
  }
  echo "Uploaded and verified GCS backup object: $object"
done
