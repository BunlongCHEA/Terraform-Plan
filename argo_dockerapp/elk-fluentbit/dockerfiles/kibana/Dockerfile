# =============================================================
# Kibana — Dockerfile
#
# Build:  docker build -t <registry>/kyc-kibana:latest .
# Push :  docker push  <registry>/kyc-kibana:latest
# =============================================================
# FROM docker.elastic.co/kibana/kibana:8.15.3
FROM docker.elastic.co/kibana/kibana:9.4.4

COPY kibana.yml /usr/share/kibana/config/kibana.yml

EXPOSE 5601
