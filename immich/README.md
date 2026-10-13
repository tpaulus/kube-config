# Immich

Immich stores its photo and video library on the TrueNAS NFS share
`woodlandpark.brickyard.whitestar.systems:/mnt/tank/Photos`. The PV advertises
1 Ti for Kubernetes binding; NFS does not enforce that as a quota.

Before syncing the application, create the 1Password item at
`vaults/K3S/items/immich-db` with `username`, `password`, and `database` fields.
Use `immich` for the database name. The OnePassword operator publishes that
item as the `immich-db` Secret in the `immich` namespace.
