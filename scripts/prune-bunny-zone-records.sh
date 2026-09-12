#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: BUNNY_API_KEY=... scripts/prune-bunny-zone-records.sh --zone example.com [--apply]

Lists the A, CNAME, MX, TXT, and SRV records in a Bunny DNS zone by default. Add
--apply to delete the listed records after typing the exact zone name.

All other Bunny record types are preserved, including AAAA, PV, and RDR
records. The following names are always preserved when present:
lfp-primary.it.paulus.family, lfp.it.paulus.family,
lfp-backup.it.paulus.family, and vista.whitestar.systems.
EOF
}

zone=
apply=false

while (($#)); do
  case "$1" in
    --zone)
      zone=${2:?--zone requires a domain}
      shift 2
      ;;
    --apply)
      apply=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

: "${BUNNY_API_KEY:?Set BUNNY_API_KEY before running this script.}"
: "${zone:?Pass --zone example.com.}"
command -v curl >/dev/null || { echo "curl is required." >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required." >&2; exit 1; }

zones=$(mktemp)
records=$(mktemp)
candidates=$(mktemp)
protected=$(mktemp)
trap 'rm -f "$zones" "$records" "$candidates" "$protected"' EXIT

curl --fail --silent --show-error \
  --header "AccessKey: $BUNNY_API_KEY" \
  'https://api.bunny.net/dnszone?perPage=1000' >"$zones"

zone_id=$(jq -r --arg zone "$zone" '
  [.Items[] | select(.Domain == $zone) | .Id] |
  if length == 1 then .[0] else empty end
' "$zones")

if [[ -z "$zone_id" ]]; then
  echo "Expected exactly one Bunny zone named $zone; none or multiple were found." >&2
  exit 1
fi

curl --fail --silent --show-error \
  --header "AccessKey: $BUNNY_API_KEY" \
  "https://api.bunny.net/dnszone/$zone_id" >"$records"

# Bunny DNS API record types: A=0, CNAME=2, TXT=3, MX=4, SRV=8.
jq -r --arg zone "$zone" '
  def record_name:
    if .Name == "" or .Name == "@" then $zone
    elif (.Name | endswith(".")) then .Name | rtrimstr(".")
    elif (.Name | endswith("." + $zone)) then .Name
    else .Name + "." + $zone
    end;
  def selected_type: .Type == 0 or .Type == 2 or .Type == 3 or .Type == 4 or .Type == 8;
  def protected_name:
    record_name as $name
    | $name == "lfp-primary.it.paulus.family"
      or $name == "lfp.it.paulus.family"
      or $name == "lfp-backup.it.paulus.family"
      or $name == "vista.whitestar.systems";

  .Records[]
  | select(selected_type and (protected_name | not))
  | [.Id, .Type, .Name, .Value] | @tsv
' "$records" >"$candidates"

jq -r --arg zone "$zone" '
  def record_name:
    if .Name == "" or .Name == "@" then $zone
    elif (.Name | endswith(".")) then .Name | rtrimstr(".")
    elif (.Name | endswith("." + $zone)) then .Name
    else .Name + "." + $zone
    end;
  def selected_type: .Type == 0 or .Type == 2 or .Type == 3 or .Type == 4 or .Type == 8;
  def protected_name:
    record_name as $name
    | $name == "lfp-primary.it.paulus.family"
      or $name == "lfp.it.paulus.family"
      or $name == "lfp-backup.it.paulus.family"
      or $name == "vista.whitestar.systems";

  .Records[]
  | select(selected_type and protected_name)
  | [.Id, .Type, record_name, .Value] | @tsv
' "$records" >"$protected"

count=$(wc -l <"$candidates" | tr -d ' ')
printf 'Zone: %s (ID %s)\nCandidate records: %s\n\n' "$zone" "$zone_id" "$count"
printf 'ID\tTYPE\tNAME\tVALUE\n'
awk -F '\t' 'BEGIN { OFS="\t" } {
  type = ($2 == 0 ? "A" : ($2 == 2 ? "CNAME" : ($2 == 3 ? "TXT" : ($2 == 4 ? "MX" : "SRV"))))
  print $1, type, ($3 == "" ? "@" : $3), $4
}' "$candidates"

if [[ -s "$protected" ]]; then
  printf '\nProtected records (not selected for deletion):\n'
  awk -F '\t' 'BEGIN { OFS="\t" } {
    type = ($2 == 0 ? "A" : ($2 == 2 ? "CNAME" : ($2 == 3 ? "TXT" : ($2 == 4 ? "MX" : "SRV"))))
    print $1, type, $3, $4
  }' "$protected"
fi

if [[ "$apply" != true ]]; then
  printf '\nDry run only. Re-run with --apply to delete exactly these %s records.\n' "$count"
  exit 0
fi

read -r -p "Type the exact zone name ($zone) to delete these records: " confirmation
if [[ "$confirmation" != "$zone" ]]; then
  echo "Confirmation did not match; no records were deleted." >&2
  exit 1
fi

while IFS=$'\t' read -r record_id _ _ _; do
  curl --fail --silent --show-error --request DELETE \
    --header "AccessKey: $BUNNY_API_KEY" \
    "https://api.bunny.net/dnszone/$zone_id/records/$record_id"
  printf 'Deleted record ID %s\n' "$record_id"
done <"$candidates"

printf 'Deleted %s A, CNAME, MX, TXT, and SRV records from %s.\n' "$count" "$zone"
