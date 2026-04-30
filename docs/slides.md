# Slide 1 - Problem statement
- Build platform infrastructure to ingest and persist user events from web/mobile apps.
- Ensure durability and downstream analytics readiness.

# Slide 2 - Requirements and assumptions
- 1M events/day, ~1.5KB each.
- AWS, IaC, CI/CD, secure ingestion, scalable and HA.

# Slide 3 - High-level architecture
- API Gateway -> Lambda -> Firehose -> S3 -> Glue/Athena.
- Managed serverless-first design.

# Slide 4 - Ingestion path design
- `POST /events` endpoint.
- Shared-secret auth via `x-api-key`.
- Validation + normalization in Lambda.

# Slide 5 - Persistence path design
- Firehose buffers and compresses records.
- Partitioned S3 raw data lake (`year/month/day`).
- Query with Athena through Glue catalog.

# Slide 6 - NFR coverage
- HA: managed multi-AZ services.
- Scalability: service-native autoscaling.
- Security: TLS, IAM least privilege, SSE-S3.

# Slide 7 - Cost estimate math
- 1M/day = 30M/month requests.
- ~45GB/month raw storage.
- Estimated $40-$120/month baseline + Athena query spend.

# Slide 8 - 10x scale improvements
- Move to Parquet.
- Introduce schema registry.
- Stronger auth and producer governance.

# Slide 9 - Operational story
- CloudWatch logs for API, Lambda, Firehose.
- Alarm strategy: error rate, throttle, failed puts.
- Failure modes and graceful degradation.

# Slide 10 - Open questions
- Real-time consumer needs?
- Data retention policy by event type?
- DR posture (single-region vs multi-region)?
