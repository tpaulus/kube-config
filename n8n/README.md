# Alertmanager Todoist workflow

The published n8n workflow **Alertmanager Todoist Tasks** receives Alertmanager notifications at:

```text
http://n8n-service.n8n.svc.cluster.local/webhook/alertmanager-todoist
```

It creates Todoist tasks in the `IT 💻` project for alerts routed with the `todoist` notification token. Active alert fingerprints are stored in the `alertmanager_todoist_tasks` n8n Data Table so repeat firing notifications do not create duplicates. Resolved notifications complete the mapped task, and a later firing creates a new task.

Runtime workflow ID: `AD2g0TNcZVuqDm4r`

The workflow uses the existing `Todoist account` n8n credential. Do not commit credential values. Manage the workflow through the configured n8n MCP server or n8n UI, and keep the workflow published after changes.

Failures are handled by the published **n8n Error Email Notification** workflow (`HeYDiZsTfsVgwQYk`), which sends the workflow name, execution ID, error, and execution URL to `tom@tompaulus.com` using the configured SMTP credential.
