# =============================================================
# RabbitMQ (single node, with management UI) — Dockerfile
#
# Build:  docker build -t <registry>/kyc-rabbitmq:latest .
# Push :  docker push  <registry>/kyc-rabbitmq:latest
# =============================================================
FROM rabbitmq:3.13-management

# Bake in which plugins are enabled — management UI + prometheus metrics
# exporter, so it can optionally later be scraped by your existing
# Prometheus/Grafana stack.
COPY enabled_plugins /etc/rabbitmq/enabled_plugins
COPY rabbitmq.conf /etc/rabbitmq/rabbitmq.conf

EXPOSE 5672 15672 15692
