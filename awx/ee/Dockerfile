FROM quay.io/ansible/awx-ee:24.6.1

USER root

COPY requirements.yml /tmp/requirements.yml
COPY requirements.txt /tmp/requirements.txt

RUN python3 -m pip install --no-cache-dir -r /tmp/requirements.txt && \
    ansible-galaxy collection install -r /tmp/requirements.yml && \
    ansible-galaxy role install -r /tmp/requirements.yml && \
    rm -f /tmp/requirements.yml /tmp/requirements.txt
