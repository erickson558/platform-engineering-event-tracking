# User Events Tracking Platform (AWS)

This repository contains a production-intent solution for the Platform Engineering take-home challenge.

## Chosen path

I chose **Path B (ship deployable IaC + code)** to maximize clarity and reviewer reproducibility without requiring access to a personal AWS account.

## Architecture at a glance

- Ingestion endpoint: API Gateway HTTP API (`POST /events`)
- Compute: AWS Lambda (Python 3.12)
- Durable storage path: Kinesis Data Firehose -> S3 (GZIP JSON)
- Query layer: AWS Glue Catalog + Athena workgroup

Detailed architecture: `ARCHITECTURE.md`

## Why this design

- **HA:** API Gateway, Lambda, Firehose, and S3 are managed multi-AZ services.
- **Scalability:** Auto-scaling managed ingestion; no manual capacity management in baseline path.
- **Security:** TLS in transit, API shared secret, IAM least privilege, encrypted S3 bucket.
- **Cost effectiveness:** Pay-per-use serverless stack aligned with 1M events/day.

## Repository structure

```text
.
├── .github/workflows/ci.yml
├── app/ingestion/handler.py
├── app/ingestion/tests/test_handler.py
├── terraform/main.tf
├── terraform/variables.tf
├── terraform/outputs.tf
├── ARCHITECTURE.md
├── adr/0001-ingestion-and-storage.md
└── docs/slides.md
```

## Prerequisites

- Terraform >= 1.6
- AWS CLI configured with credentials
- Python 3.12 (for local tests)

## Deploy

```bash
cd terraform
terraform init
terraform plan -var="api_shared_secret=replace-me"
terraform apply -var="api_shared_secret=replace-me"
```

## Send a test event

After apply, get endpoint:

```bash
terraform output api_base_url
```

Then call ingestion endpoint:

```bash
curl -X POST "${API_BASE_URL}/events" \
  -H "content-type: application/json" \
  -H "x-api-key: replace-me" \
  -d '{
    "event_name":"sign_in",
    "event_timestamp":"2026-04-29T17:00:00Z",
    "source":"web",
    "user_id":"u-123",
    "payload":{"method":"password"}
  }'
```

Expected response:

```json
{"accepted":1,"failed":0}
```

## Query persisted data (Athena)

1. Create partitions:

```sql
MSCK REPAIR TABLE user_events;
```

2. Sample query:

```sql
SELECT event_name, count(*)
FROM user_events
GROUP BY event_name
ORDER BY count(*) DESC;
```

## CI/CD workflow

`/.github/workflows/ci.yml` includes:

- Terraform format check
- Terraform validate
- TFLint
- tfsec security scan
- Terraform plan on PRs
- Deploy on merge to `main` (when AWS OIDC role is configured)

For deploy job, set repository secrets/variables:

- `AWS_ROLE_TO_ASSUME`
- `TF_VAR_api_shared_secret`

## Cost estimate (1M events/day)

Assumptions:

- Payload size: ~1.5 KB/event
- Volume: ~1.5 GB/day (~45 GB/month raw)
- Single-region deployment, us-east-1 pricing ballpark

Estimated monthly cost:

- API Gateway HTTP API: low tens of USD for 30M requests/month
- Lambda ingestion: low single-digit to low tens USD (short runtime)
- Firehose ingest/delivery: low tens USD
- S3 storage (~45 GB + overhead): low single-digit USD
- Athena scan costs depend on query patterns

Ballpark total: **~$40-$120/month** before heavy Athena usage.

## Assumptions and non-goals

- Authentication uses shared secret for simplicity in challenge scope.
- Schema enforcement is minimal (required fields only).
- No backfill/replay tooling included.

## 10x scale notes (10M/day)

- Move auth to JWT with per-client identity.
- Add event schema registry and compatibility checks.
- Optimize Firehose format to Parquet and partition strategy for Athena efficiency.
- Consider Kinesis Data Streams if near real-time consumers become required.

## What I would add with more time

- End-to-end tests with LocalStack.
- CloudWatch dashboards and alarms.
- DLQ/retry observability for partial delivery failures.
- Multi-region DR strategy with explicit RTO/RPO.
