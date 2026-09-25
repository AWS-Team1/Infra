#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  echo "usage: $0 <backup-directory> <bucket> <region> <object-prefix>" >&2
  exit 2
}

BACKUP_DIR=${1:-}
BUCKET=${2:-}
REGION=${3:-}
OBJECT_PREFIX=${4:-}

[[ -d "$BACKUP_DIR" && -n "$BUCKET" && -n "$REGION" && -n "$OBJECT_PREFIX" ]] || usage
[[ "$OBJECT_PREFIX" != /* && "$OBJECT_PREFIX" != */ && "$OBJECT_PREFIX" != *..* ]] || {
  echo "unsafe S3 object prefix: $OBJECT_PREFIX" >&2
  exit 2
}
[[ -s "$BACKUP_DIR/metadata.json" ]] || { echo "metadata.json is missing or empty" >&2; exit 1; }
[[ -s "$BACKUP_DIR/SHA256SUMS" ]] || { echo "SHA256SUMS is missing or empty" >&2; exit 1; }

(
  cd "$BACKUP_DIR"
  sha256sum --check --strict SHA256SUMS >/dev/null
)

actual_region=$(aws s3api get-bucket-location \
  --bucket "$BUCKET" \
  --region "$REGION" \
  --query 'LocationConstraint' \
  --output text)
[[ "$actual_region" == "$REGION" ]] || {
  echo "Backup bucket region mismatch: expected $REGION, got $actual_region" >&2
  exit 1
}

mapfile -d '' backup_files < <(find "$BACKUP_DIR" -maxdepth 1 -type f -print0 | sort -z)
(( ${#backup_files[@]} > 0 )) || { echo "No backup files found" >&2; exit 1; }

for file in "${backup_files[@]}"; do
  name=$(basename -- "$file")
  key="$OBJECT_PREFIX/$name"
  size=$(stat -c '%s' "$file")
  checksum=$(openssl dgst -sha256 -binary "$file" | base64 | tr -d '\n')

  aws s3api put-object \
    --bucket "$BUCKET" \
    --key "$key" \
    --body "$file" \
    --region "$REGION" \
    --server-side-encryption AES256 \
    --checksum-algorithm SHA256 \
    --checksum-sha256 "$checksum" \
    --if-none-match '*' >/dev/null

  read -r remote_size remote_checksum < <(
    aws s3api head-object \
      --bucket "$BUCKET" \
      --key "$key" \
      --region "$REGION" \
      --checksum-mode ENABLED \
      --query '[ContentLength,ChecksumSHA256]' \
      --output text
  )
  [[ "$remote_size" == "$size" && "$remote_checksum" == "$checksum" ]] || {
    echo "Uploaded object verification failed: $key" >&2
    exit 1
  }
  echo "Uploaded and verified backup object: $key"
done
