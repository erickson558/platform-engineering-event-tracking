# ADR 0001: Use API Gateway + Lambda + Firehose + S3 for Event Tracking

## Status
Accepted

## Context
We need a highly available and scalable ingestion path for ~1M events/day with minimal operational burden, while keeping data durable and queryable for analytics teams.

## Decision
Use:

- API Gateway (HTTP API) as public ingestion endpoint.
- Lambda (Python) for authentication and event validation.
- Kinesis Data Firehose for durable buffered delivery.
- S3 as raw event store.
- Glue + Athena for downstream queryability.

## Alternatives Considered

- API Gateway direct to Kinesis Data Streams + consumer apps: more moving parts and on-call burden.
- ECS/Fargate ingestion service + queue + workers: stronger control but higher operational overhead for this scale.
- Kafka/MSK: overkill for initial scale and expensive to operate.

## Consequences

Positive:

- Strong managed-service posture with low ops load.
- HA and scale-out behavior are mostly service-native.
- Clear path to analytics consumption via Athena.

Negative:

- Firehose buffering introduces ingest-to-query delay.
- Shared-secret auth is simple but weaker than mTLS or JWT-based auth.

## Follow-ups

- Move client auth to JWT/OIDC or request signing.
- Add schema registry / contract validation for evolution.
- Introduce DLQ and replay pipeline for failed delivery records.
