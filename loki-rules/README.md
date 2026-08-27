# Databasus Backup Monitoring

Databasus backups are monitored with Loki ruler alerts, not Kubernetes
CronJob status. The alert is based on Databasus's `logical backup finished`
event, which is emitted only after the encrypted backup is written to its
configured storage.

## Adding a database

1. Configure the database, storage, backup schedule, and failure notifications
   in the Databasus UI.
2. Run or wait for the first successful backup. Confirm its completion in the
   Databasus pod logs and record the stable `database_id`:

   ```sh
   kubectl logs -n databasus statefulset/databasus -c databasus \
     | grep 'logical backup finished'
   ```

3. Add a `DatabasusBackupStale` rule to
   `loki-rules/databasus-backups.yaml`. Match both
   `logical backup finished` and that database's `database_id`.
4. Select a lookback window that allows for normal schedule delay:
   - Hourly schedules: `2h`
   - Daily schedules: `26h`
   - Other schedules: at least the configured interval plus a reasonable
     execution and recovery margin
5. Keep `for: 5m`, set the human-readable `database` label, and update the
   summary and description.

Example:

```yaml
- alert: DatabasusBackupStale
  expr: absent_over_time({namespace="databasus", container="databasus"} |= "logical backup finished" |= "database_id=<DATABASE_UUID>" [2h])
  for: 5m
  labels:
    severity: high
    notify: todoist email-tom
    database: Example
  annotations:
    summary: Databasus backup overdue for Example
    description: Databasus has not completed an Example backup in over two hours.
```

The ConfigMap must retain `loki_rule: "true"` and the
`k8s-sidecar-target-directory: fake` annotation. Loki's rule sidecar loads it
from `/rules/fake`, and Loki forwards firing alerts to Alertmanager at
`alertmanager.monitoring.svc:8080`.

After Argo CD syncs the change, verify that Loki loaded the rules:

```sh
kubectl run -n loki loki-query --rm -i --restart=Never \
  --image=curlimages/curl:8.21.0 -- \
  curl -fsS http://loki.loki.svc:3100/loki/api/v1/rules
```
