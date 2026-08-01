# =============================================================
# Elasticsearch (single-node, logging cluster) — Dockerfile
#
# Build:  docker build -t <registry>/kyc-elasticsearch:latest .
# Push :  docker push  <registry>/kyc-elasticsearch:latest
# =============================================================
# FROM docker.elastic.co/elasticsearch/elasticsearch:8.15.3
FROM docker.elastic.co/elasticsearch/elasticsearch:9.4.4

# Bake in our single-node config (security kept on, but no external TLS —
# fine for an internal cluster-local logging namespace behind ArgoCD/Traefik).
COPY elasticsearch.yml /usr/share/elasticsearch/config/elasticsearch.yml

# jvm heap kept modest for a Raspberry Pi class node — override with
# ES_JAVA_OPTS env var in the k8s manifest if the host has more RAM.
ENV ES_JAVA_OPTS="-Xms512m -Xmx512m"

EXPOSE 9200 9300
