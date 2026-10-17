#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
qrscout_source="$repository_root/work/QRScout-Legacy-public"
payload="$("$qrscout_source/scripts/test.sh" --emit-scanner-payload)"

if [[ "$payload" != QRSCOUT3-* ]]; then
    echo "QRScout did not emit a compact version 3 scanner record." >&2
    exit 1
fi

if (( ${#payload} > 245 )); then
    echo "QRScout emitted ${#payload} characters, exceeding the S-1103T's 245-character limit." >&2
    exit 1
fi

QRSCOUT_CONTRACT_PAYLOAD="$payload" swift test \
    --package-path "$repository_root" \
    --filter SpreadsheetStoreTests/testPayloadProducedByExternalQRScoutGeneratorWhenProvided

QRSCOUT_CONTRACT_PAYLOAD="$payload" node - "$repository_root/Windows/src/core.js" <<'NODE'
const core = require(process.argv[2]);
const expected = [
  "AJ", "12", "8324", "Outpost Trench", "false", "500", "Outpost, Neutral Zone", "Passed, Bump", "true", "C",
  "450", "Bump, Trench", "true", "300", "Collecting, Defense", "L3", "true", "false", "true",
  "5", "both", "Outpost Trench, Hub", "4", "stationary", "5", "Yellow", "Yes", "May", "solid"
];
const result = core.ingestScan(core.createDocument(), process.env.QRSCOUT_CONTRACT_PAYLOAD);
const actual = result.document.columns.map((column) => result.document.rows[0].values[column.id] || "");
if (!result.accepted || result.document.rows.length !== 2 || JSON.stringify(actual) !== JSON.stringify(expected)) {
  throw new Error(`Windows intake mismatch:\nexpected=${JSON.stringify(expected)}\nactual=${JSON.stringify(actual)}`);
}
console.log("Windows QRScout contract round-trip passed.");
NODE

QRSCOUT_CONTRACT_PAYLOAD="$payload" xcrun swift "$repository_root/scripts/qr-image-roundtrip.swift"

echo "Native QRScout → QR image → macOS FieldScout → Windows FieldScout verification passed."
