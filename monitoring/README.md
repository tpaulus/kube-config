Source: https://github.com/techiescamp/kubernetes-prometheus/tree/master

## Non-K3s reboot monitoring

Ansible exports `node_reboot_required` through the node-exporter textfile
collector on non-K3s Debian compute/storage hosts every minute: `1` when
`/run/reboot-required` exists, otherwise `0`. The `netbox-devices` scrape job
discovers active devices via NetBox and retains all metrics, including this gauge.
Hosts must already be registered for node-exporter discovery in NetBox.

`NodeRebootRequired` in `_alerts/node-exporter.yaml` evaluates
`node_reboot_required == 1` per host with `for: 24h`. It uses `severity: warning`
and `notify: todoist email-tom`, matching the existing Kured reboot alert's
routing. A zero or stale metric clears the alert and resets its pending timer;
missing metrics do not indicate a healthy host (the existing `Node down` rule
handles unreachable exporters). The existing Kured `RebootRequired` alert is
unchanged.

## NAS Restic integrity checks

`ShareIntegrity` in `_alerts/nas.yaml` monitors the scheduled NAS Restic checks.
Ansible installs `b2_check_expected{share,bucket_name}=1` independently of check
results for each backup-enabled repository (currently Photos, Docs, Mel, Tom,
Archive, Jellyfin, Prometheus and WebDAV in `brickyard-woodlandpark-restic`).
Each run atomically replaces its result textfile with either
`b2_check_completed` (Unix timestamp of success) or `b2_check_failed` (Unix
timestamp of failure), never both.

Checks run weekly on Sunday at 02:00 with up to 30 minutes of jitter, share the
backup lock and read a rotating quarter of repository data. The alerts are:

| Alert | Condition |
| --- | --- |
| Share Integrity Check Failed | A positive failure timestamp remains present. |
| Share Integrity Check Overdue | The success timestamp is more than 8 days old. |
| Share Integrity Check Missing | An expected repository has neither result, including before its first run. |

All three wait 10 minutes and use `severity: high` and `notify: todoist email-tom`.
They match on `netbox_device_name`, `share` and `bucket_name`, aggregating away
scrape-specific labels, and require a healthy node-exporter target using the
existing NetBox host and port-9100 discovery pattern. An exporter outage or
removed target is covered by the existing `Node down` / `NAS Maintenance Target
Missing` alerts instead. A later success clears a failure; a failed-only result
raises the failure alert, not the missing or overdue alert. Missing-result
detection depends on the independently installed expectation metric.
