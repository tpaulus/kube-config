kubectl apply -f netbox-namespace.yaml

helm install netbox-redis --namespace netbox oci://registry-1.docker.io/bitnamicharts/redis -f redis-values.yaml
helm upgrade netbox-redis --namespace netbox oci://registry-1.docker.io/bitnamicharts/redis -f redis-values.yaml