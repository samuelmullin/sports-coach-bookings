#!/bin/sh
# Creates the local MinIO bucket used to exercise the real S3 storage backend.
# Run by the minio-init service in docker-compose.yml. Dev-only credentials.
set -eu

mc alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"
mc mb --ignore-existing "local/${S3_BUCKET:-scb-uploads}"
mc anonymous set none "local/${S3_BUCKET:-scb-uploads}"
