FROM python:3.15-slim-trixie

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git openssh-client webhook \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /opt/runner/requirements.txt
RUN pip install --no-cache-dir -r /opt/runner/requirements.txt \
    && useradd --uid 10001 --create-home runner

COPY runner.py hooks.json.tmpl github_known_hosts /opt/runner/
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 HOME=/work
USER 10001:10001
WORKDIR /work
ENTRYPOINT ["python", "/opt/runner/runner.py"]
