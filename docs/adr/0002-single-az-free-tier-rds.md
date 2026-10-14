# ADR-0002: Single-AZ free-tier RDS in prod

**Status:** Accepted
**Date:** 2026-10-14
**Context:** PETPLAT-27 keeps prod on `db.t4g.micro` with `multi_az = false` and `deletion_protection = false` to stay within the AWS free tier for this learning project (technical-spec.md → RDS Database cost note). A reviewer cannot tell from the code alone whether prod is cheap by decision or by oversight.
**Decision:** Accept single-AZ, no Multi-AZ, no deletion protection in prod. The recovery path is 30-day automated backups plus a final snapshot on destroy (`skip_final_snapshot = false`, unique `-final-{random}` name). In a real production deployment: Multi-AZ, `db.r7g.large`+, gp3, deletion protection, and a static final-snapshot name managed outside Terraform.
**Consequences:** An RDS availability-zone outage means downtime until a cross-AZ restore completes (RTO in tens of minutes, not seconds); `terraform destroy` can delete the prod database (final snapshot is the only guard); storage autoscaling to 100 GB bounds the storage-full risk. Positive: ~$0/mo RDS cost keeps the course under budget.
