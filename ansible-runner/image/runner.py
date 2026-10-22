"""Run the trusted Ansible entry point, or submit it from an authenticated hook."""

import copy
import json
import os
import re
import shutil
import subprocess
import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path

from kubernetes import client, config
from kubernetes.client.exceptions import ApiException

NAMESPACE = os.environ.get("POD_NAMESPACE", "ansible-runner")
CRONJOB = "ansible-apply"
LEASE = "ansible-apply"
LEASE_SECONDS = 18000
MAX_JOB_SECONDS = 14400


def acquire_lock(api, holder, now):
    lease = api.read_namespaced_lease(LEASE, NAMESPACE)
    spec = lease.spec
    if spec.holder_identity:
        renewed = spec.renew_time or spec.acquire_time
        if renewed is None or spec.lease_duration_seconds is None:
            raise RuntimeError(
                "Occupied Lease has no expiry; manual investigation required"
            )
        if renewed + timedelta(seconds=spec.lease_duration_seconds) > now:
            raise RuntimeError(
                "Another Ansible run holds the Lease; retry after it finishes"
            )
    lease.spec = client.V1LeaseSpec(
        holder_identity=holder,
        lease_duration_seconds=LEASE_SECONDS,
        acquire_time=now,
        renew_time=now,
    )
    # resourceVersion makes simultaneous acquisitions mutually exclusive.
    api.replace_namespaced_lease(LEASE, NAMESPACE, lease)


def release_lock(api, holder):
    lease = api.read_namespaced_lease(LEASE, NAMESPACE)
    if lease.spec.holder_identity != holder:
        raise RuntimeError("Ansible Lease ownership changed unexpectedly")
    lease.spec = client.V1LeaseSpec(lease_duration_seconds=LEASE_SECONDS)
    api.replace_namespaced_lease(LEASE, NAMESPACE, lease)


def command(*args, **kwargs):
    try:
        return subprocess.run(args, check=True, **kwargs)
    except subprocess.CalledProcessError as error:
        if error.stdout:
            output = error.stdout
            if isinstance(output, bytes):
                output = output.decode(errors="replace")
            print(output, file=sys.stderr, end="" if output.endswith("\n") else "\n")
        raise


def apply():
    secrets = Path("/secrets")
    for name in ("ssh_key", "vault_password"):
        if not (secrets / name).read_text().strip():
            raise RuntimeError(f"Required credential file is empty: {name}")
    if not os.environ.get("NETBOX_TOKEN") or not os.environ.get("ANSIBLE_REMOTE_USER"):
        raise RuntimeError("NETBOX_TOKEN and ANSIBLE_REMOTE_USER are required")

    ssh = Path("/work/.ssh")
    ssh.mkdir(mode=0o700)
    shutil.copyfile(secrets / "ssh_key", ssh / "ssh_key")
    (ssh / "ssh_key").chmod(0o600)
    (ssh / "known_hosts").touch(mode=0o600, exist_ok=True)

    os.environ.update(
        GIT_SSH_COMMAND=(
            "ssh -i /work/.ssh/ssh_key -o IdentitiesOnly=yes "
            "-o StrictHostKeyChecking=yes "
            "-o UserKnownHostsFile=/opt/runner/github_known_hosts "
            "-o GlobalKnownHostsFile=/dev/null"
        ),
        GIT_TERMINAL_PROMPT="0",
        ANSIBLE_PRIVATE_KEY_FILE="/work/.ssh/ssh_key",
        ANSIBLE_HOST_KEY_CHECKING="True",
        ANSIBLE_SSH_ARGS=(
            "-o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new "
            "-o UserKnownHostsFile=/work/.ssh/known_hosts "
            "-o GlobalKnownHostsFile=/opt/runner/github_known_hosts"
        ),
        ANSIBLE_CONFIG="/work/repository/ansible.cfg",
        ANSIBLE_VAULT_IDENTITY_LIST="op://Infra/Ansible/password@/secrets/vault_password",
        ANSIBLE_INVENTORY_ANY_UNPARSED_IS_FAILED="True",
    )
    command(
        "git",
        "clone",
        "--depth",
        "1",
        "--single-branch",
        "--branch",
        os.environ["ANSIBLE_BRANCH"],
        "--",
        os.environ["ANSIBLE_REPOSITORY"],
        "/work/repository",
    )
    os.chdir("/work/repository")
    command("git", "rev-parse", "HEAD")
    command(
        "ansible-galaxy",
        "role",
        "install",
        "-r",
        "requirements.yml",
        "--roles-path",
        ".ansible/roles",
    )
    command(
        "ansible-galaxy",
        "collection",
        "install",
        "-r",
        "requirements.yml",
        "--collections-path",
        ".ansible/collections",
    )
    inventory = json.loads(
        command("ansible-inventory", "--list", stdout=subprocess.PIPE, text=True).stdout
    )
    if not inventory.get("_meta", {}).get("hostvars"):
        raise RuntimeError(
            "Production inventory contains no hosts; refusing an empty successful run"
        )
    # No --limit: site.yml applies to every inventory host using its existing scopes.
    command("ansible-playbook", "playbooks/site.yml")


def run(trigger):
    if trigger not in ("scheduled", "webhook"):
        raise ValueError("Unknown run trigger")
    now = datetime.now(UTC)
    config.load_incluster_config()
    api = client.CoordinationV1Api()
    holder = os.environ["POD_UID"]
    acquire_lock(api, holder, now)
    try:
        apply()
    finally:
        release_lock(api, holder)


def submit(batch, revision):
    if not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("Invalid GitHub push commit")
    if revision == "0" * 40:
        raise ValueError("Deleted branches cannot trigger Ansible")
    cron = batch.read_namespaced_cron_job(CRONJOB, NAMESPACE)
    spec = copy.deepcopy(cron.spec.job_template.spec)
    if (
        not spec.active_deadline_seconds
        or not 0 < spec.active_deadline_seconds <= MAX_JOB_SECONDS
    ):
        raise ValueError("Job deadline must be positive and at most four hours")
    containers = spec.template.spec.containers
    if len(containers) != 1 or containers[0].name != "ansible":
        raise ValueError("Unexpected CronJob container layout")
    containers[0].args = ["run", "webhook"]
    name = f"ansible-webhook-{revision}"
    job = client.V1Job(
        api_version="batch/v1",
        kind="Job",
        metadata=client.V1ObjectMeta(
            name=name, labels={"app.kubernetes.io/name": "ansible-runner"}
        ),
        spec=spec,
    )
    try:
        batch.create_namespaced_job(NAMESPACE, job)
    except ApiException as error:
        if error.status != 409:
            raise
        print(f"Job {name} already submitted")
    else:
        print(f"Submitted Job {name}; inspect its status for the Ansible result")


def handle_webhook(event):
    with Path(os.environ["WEBHOOK_PAYLOAD"]).open() as source:
        payload = json.load(source)
    if payload.get("repository", {}).get("full_name") != "tpaulus/ansible":
        raise ValueError("Unexpected webhook repository")
    if event == "ping":
        print("GitHub webhook configured")
        return
    if event != "push" or payload.get("ref") != "refs/heads/main":
        raise ValueError("Only pushes to main can trigger Ansible")
    if payload.get("deleted") is not False:
        raise ValueError("Deleted branches cannot trigger Ansible")
    config.load_incluster_config()
    submit(client.BatchV1Api(), payload["after"])


def serve():
    if len(os.environ.get("WEBHOOK_SECRET", "")) < 32:
        raise ValueError("WEBHOOK_SECRET must contain at least 32 characters")
    os.execvp(
        "webhook",
        [
            "webhook",
            "-hooks=/opt/runner/hooks.json.tmpl",
            "-template",
            "-verbose",
            "-ip=0.0.0.0",
            "-port=9000",
        ],
    )


def main():
    if sys.argv[1:] == ["serve"]:
        serve()
    elif len(sys.argv) == 3 and sys.argv[1] == "run":
        run(sys.argv[2])
    elif len(sys.argv) == 3 and sys.argv[1] == "submit":
        handle_webhook(sys.argv[2])
    else:
        raise ValueError(
            "Usage: runner.py serve | run scheduled|webhook | submit push|ping"
        )


if __name__ == "__main__":
    main()
