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
