# Fleet

Fleet is deployed at `https://mdm.it.paulus.family` with MySQL and Redis
services in this namespace. The ingress terminates TLS; Fleet listens for HTTP
traffic inside the cluster.

Create the 1Password item `Fleet` in the `K3S` vault with these fields:

- `MYSQL_ROOT_PASSWORD`: strong MySQL root password
- `MYSQL_PASSWORD`: strong password for Fleet's MySQL user
- `FLEET_SERVER_PRIVATE_KEY`: output of `openssl rand -base64 32`

This deployment uses Fleet's free tier. Fleet data, logs, vulnerability
databases, MySQL, and Redis are stored on persistent volume claims.
