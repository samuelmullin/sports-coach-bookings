#!/bin/sh
# Creates the local object-storage buckets used to exercise the real S3 backends:
# a public-assets bucket and a private bucket for signed-waiver PDFs.
# Run by the rustfs-init service in docker-compose.yml. Dev-only credentials.
# Uses the AWS CLI, so it works against any S3-compatible server.
set -eu

ENDPOINT="${S3_ENDPOINT:-http://rustfs:9000}"

# RustFS may still be starting; retry until it answers.
i=0
until aws --endpoint-url "$ENDPOINT" s3api list-buckets >/dev/null 2>&1; do
  i=$((i + 1))
  [ "$i" -gt 30 ] && { echo "RustFS did not become ready at $ENDPOINT" >&2; exit 1; }
  sleep 2
done

for bucket in "${S3_BUCKET:-scb-uploads}" "${S3_PRIVATE_BUCKET:-scb-private}"; do
  aws --endpoint-url "$ENDPOINT" s3api head-bucket --bucket "$bucket" 2>/dev/null \
    || aws --endpoint-url "$ENDPOINT" s3api create-bucket --bucket "$bucket"
  echo "bucket ready: $bucket"
done
