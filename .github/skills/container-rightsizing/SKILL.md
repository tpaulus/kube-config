---
name: container-rightsizing
description: Review Kubernetes CPU and memory utilization, then safely right-size resource requests and limits in this repository.
---

# Container rightsizing

Use this skill for periodic capacity reviews and before adding workloads that do
not schedule because of resource requests.

## Collect evidence

1. Confirm node capacity, current scheduler reservations, and pending pods:

   ```sh
   kubectl get nodes -o custom-columns=NAME:.metadata.name,CPU-CAPACITY:.status.capacity.cpu,CPU-ALLOCATABLE:.status.allocatable.cpu
   kubectl describe nodes
   kubectl top nodes
   kubectl top pods -A --containers --sort-by=cpu
   kubectl get pods -A --field-selector=status.phase=Pending -o wide
   kubectl get events -A --field-selector=reason=FailedScheduling --sort-by=.lastTimestamp
   ```

2. Query the in-cluster Prometheus API for a representative period. Prefer a
   14-day CPU peak based on hourly samples, which captures periodic jobs without
   making the query prohibitively expensive:

   ```sh
   PROMETHEUS=https://prometheus.ing.k3s.brickyard.whitestar.systems
   curl -G --silent --show-error "$PROMETHEUS/api/v1/query" \
     --data-urlencode 'query=topk(100, max by (namespace,pod,container) (max_over_time((rate(container_cpu_usage_seconds_total{container!="",image!=""}[5m]))[14d:1h])))'
   ```

3. When available, query
   `http://woodlandpark.brickyard.whitestar.systems:9090` for a longer
   retention window. First verify that it has Kubernetes container and
   kube-state-metrics series; do not treat unrelated node-exporter data as
   workload utilization.

## Choose values

- Kubernetes schedules on **requests**, not CPU limits. Reduce a request only
  when the observed peak leaves adequate headroom for its workload.
- Keep or raise a CPU limit for bursty, user-facing, backup, or batch
  workloads unless throttling evidence supports lowering it. A higher limit
  than request is intentional CPU oversubscription.
- Preserve equal request and limit only when Guaranteed QoS is a documented
  requirement. Do not lower memory values as part of a CPU-only review.
- Do not size from a single `kubectl top` snapshot. Investigate peaks, cron
  schedules, recent rollouts, and containers without historical samples.
- Review multi-replica workloads per replica and account for rollout surge
  capacity before applying a change.

## Apply and validate

1. Edit the owning manifest's `resources.requests.cpu` and
   `resources.limits.cpu`; retain the existing quantity style.
2. Run the repository manifest validation workflow locally when its tools are
   available, or at minimum:

   ```sh
   kubectl apply --dry-run=server -f <changed-manifest>
   ```

3. After GitOps sync, confirm pending pods schedule and review
   `kubectl describe nodes` plus CPU throttling and utilization for at least
   one normal workload cycle.
