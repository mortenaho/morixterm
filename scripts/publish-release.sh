#!/usr/bin/env bash

set -euo pipefail

tag="${1:?Release tag is required}"
assets_dir="${2:?Assets directory is required}"
repository="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

if ! gh release view "$tag" --repo "$repository" >/dev/null 2>&1; then
  gh release create "$tag" \
    --repo "$repository" \
    --title "MoriXterm $tag" \
    --generate-notes \
    --verify-tag \
    --draft
fi

for asset in "$assets_dir"/*; do
  uploaded=false

  for attempt in 1 2 3; do
    echo "Uploading $(basename "$asset") (attempt $attempt/3)..."

    if gh release upload "$tag" "$asset" --repo "$repository" --clobber; then
      uploaded=true
      break
    fi

    if [[ "$attempt" -lt 3 ]]; then
      sleep $((attempt * 15))
    fi
  done

  if [[ "$uploaded" != true ]]; then
    echo "Failed to upload $(basename "$asset") after 3 attempts." >&2
    exit 1
  fi
done

gh release edit "$tag" \
  --repo "$repository" \
  --draft=false \
  --latest
