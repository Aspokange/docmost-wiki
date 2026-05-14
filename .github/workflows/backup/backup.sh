#!/bin/bash
set -e

DATE=$(date +%Y-%m-%d_%H-%M-%S)
FILE="docmost_${DATE}.sql"

docker exec docmost-db pg_dump -U $DOCMOST_DB_USER $DOCMOST_DB_NAME > /tmp/$FILE

aws s3 cp /tmp/$FILE s3://docmost-backups-${ENVIRONMENT}-682135518833/

rm /tmp/$FILE