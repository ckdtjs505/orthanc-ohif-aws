#!/usr/bin/env bash
# Upload every .dcm under a directory to Orthanc through the nginx proxy.
# usage: PACS_URL=http://1.2.3.4 PACS_USER=admin PACS_PASSWORD=... ./upload.sh DIR
set -euo pipefail
DIR=${1:?usage: upload.sh DIR}
: "${PACS_URL:?set PACS_URL}" "${PACS_USER:=admin}" "${PACS_PASSWORD:?set PACS_PASSWORD}"

ok=0; fail=0
while IFS= read -r -d '' f; do
  if curl -sf -u "$PACS_USER:$PACS_PASSWORD" -X POST -H 'Content-Type: application/dicom' \
       --data-binary @"$f" "$PACS_URL/orthanc/instances" >/dev/null; then
    ok=$((ok + 1))
  else
    fail=$((fail + 1)); echo "failed: $f" >&2
  fi
done < <(find "$DIR" -type f -name '*.dcm' -print0)
echo "uploaded=$ok failed=$fail"
[ "$fail" -eq 0 ]
