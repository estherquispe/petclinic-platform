# Database Initialization Strategy

**Last Updated:** 2026-10-14
**Purpose:** Defines how the shared `petclinic` MySQL database on RDS is created and how the three database-backed services (customers, visits, vets) initialize their 7 tables — including init order, connection strings, and verification steps. Implements PETPLAT-24.

## Table of Contents

1. [Strategy](#strategy)
2. [Shared Database](#shared-database)
3. [Schema Scripts](#schema-scripts)
4. [Initialization Order](#initialization-order)
5. [Connection String for K8s ConfigMaps](#connection-string-for-k8s-configmaps)
6. [Credentials](#credentials)
7. [Procedure: Verify Database Initialization](#procedure-verify-database-initialization)

---

## Strategy

**Chosen approach: Spring Boot auto-initialize** (not manual SQL, not an init container).

- Each service ships its own `schema.sql` / `data.sql` under `src/main/resources/db/mysql/` in the application repo (`spring-petclinic-microservices`, read-only).
- On first startup with the `mysql` profile active, Spring Boot runs the scripts with:
  - `spring.sql.init.mode=always`
  - `spring.sql.init.schema-locations=classpath:db/mysql/schema.sql`
  - `spring.sql.init.data-locations=classpath:db/mysql/data.sql`
  - `spring.jpa.defer-datasource-initialization=true` (so Hibernate does not race the script)
- These properties are supplied as environment variables via `helm-values/{service}.yaml` (never baked into images).
- All scripts use `CREATE TABLE IF NOT EXISTS`, so restarts are idempotent.
- The init **order** is enforced by deployment order: customers-service must be Running before visits-service starts (visits has a foreign key into pets).

**Why not the alternatives:** running SQL manually or from an init container would duplicate scripts the application already owns and add a second deployer of schema changes. Spring auto-init keeps schema ownership with each service, as in the upstream project.

## Shared Database

**One database `petclinic`, shared by all three services on the single RDS instance:**

- Created by the RDS module: `db_name = "petclinic"` on `aws_db_instance` (`terraform/modules/rds/`).
- Also idempotently created by every schema script: `CREATE DATABASE IF NOT EXISTS petclinic; USE petclinic;`.
- Shared schema is confirmed by the cross-service foreign key: `visits.pet_id → pets.id` (`pets` lives in the customers-service schema) — the three services cannot use separate databases.

## Schema Scripts

| Service | Script path (app repo) | Tables created | Depends on |
|---------|------------------------|----------------|------------|
| customers-service | `spring-petclinic-customers-service/src/main/resources/db/mysql/{schema,data}.sql` | `types`, `owners`, `pets` | — |
| vets-service | `spring-petclinic-vets-service/src/main/resources/db/mysql/{schema,data}.sql` | `vets`, `specialties`, `vet_specialties` | — (independent) |
| visits-service | `spring-petclinic-visits-service/src/main/resources/db/mysql/{schema,data}.sql` | `visits` | `pets` (customers-service) |

7 tables total. `data.sql` in each service seeds reference rows (types, owners/pets, vets).

## Initialization Order

**Critical:** `visits` has `FOREIGN KEY (pet_id) REFERENCES pets(id)`.

1. **customers-service** → creates `types`, `owners`, `pets`
2. **vets-service** → creates `vets`, `specialties`, `vet_specialties` (any time after step 1)
3. **visits-service** → creates `visits` (only after step 1)

Enforced operationally: deploy customers-service first, then vets-service, then visits-service. Helm/ArgoCD rollouts keep this order per `helm-values/` startup dependencies.

## Connection String for K8s ConfigMaps

Format:

```
jdbc:mysql://{rds-endpoint}:3306/petclinic
```

Example (dev):

```
jdbc:mysql://petclinic-dev-mysql.abc123.us-east-1.rds.amazonaws.com:3306/petclinic
```

The endpoint comes from a Terraform output, never hardcoded:

```bash
terraform -chdir=terraform/environments/{env} output rds_endpoint
```

ConfigMap keys (non-secret — safe for `k8s/base/` ConfigMaps or `helm-values/`):

| Key | Value |
|-----|-------|
| `SPRING_DATASOURCE_URL` | `jdbc:mysql://{rds-endpoint}:3306/petclinic` |
| `SPRING_DATASOURCE_USERNAME` | `petclinic` (from the secret's `username` key) |
| `SPRING_PROFILES_ACTIVE` | `docker,mysql` for customers/visits/vets |

The **password** never goes in a ConfigMap — only in the Kubernetes Secret synced from Secrets Manager (see below).

## Credentials

| Item | Value |
|------|-------|
| Secret name | `petclinic/{env}/rds-credentials` |
| Format | JSON `{"username":"...","password":"..."}` |
| Created by | `terraform/modules/rds/` (PETPLAT-23, `random_password` 16 chars + special chars) |
| Consumed by | ExternalSecret `k8s/base/external-secrets/rds-credentials.yaml` → K8s Secret `rds-credentials` (PETPLAT-35) |

Fetch manually when needed (do not echo into shared logs):

```bash
aws secretsmanager get-secret-value --secret-id petclinic/{env}/rds-credentials \
  --region us-east-1 --query SecretString --output text
```

## Procedure: Verify Database Initialization

**When:** After PETPLAT-26 (`terraform apply` for dev) and after the three DB-backed services are deployed.
**Who:** on-call engineer / cluster admin (`kubectl` access to `{env}` cluster, AWS read access to Secrets Manager)
**Time:** ~10 minutes

**Steps:**

1. Confirm the RDS instance is available:

```bash
aws rds describe-db-instances --region us-east-1 \
  --db-instance-identifier petclinic-{env}-mysql \
  --query 'DBInstances[0].DBInstanceStatus'
```

2. Start a debug pod on an EKS node (RDS SG admits 3306 from the EKS node SG only):

```bash
kubectl run mysql-client-{env} --rm -it --restart=Never \
  -n petclinic-{env} --image=mysql:8.0 -- bash
```

3. Inside the pod, connect using the endpoint and credentials from Secrets Manager:

```bash
mysql -h petclinic-{env}-mysql.XXXXXXXX.us-east-1.rds.amazonaws.com -P 3306 \
  -u petclinic -p
```

4. Verify the database and all 7 tables:

```sql
USE petclinic;
SHOW TABLES;
-- expect: types, owners, pets, vets, specialties, vet_specialties, visits
SHOW CREATE TABLE visits\G
-- expect: FOREIGN KEY (pet_id) REFERENCES pets(id)
```

**Verify:**

- RDS status is `available`
- `SHOW TABLES` lists all 7 tables
- `visits.pet_id` foreign key resolves to `pets.id` (customers-service initialized first)
- K8s Secret `rds-credentials` exists in `petclinic-{env}` (synced by ExternalSecret)

**Rollback:**

- Read-only verification — nothing to roll back. If a test accidentally created objects, drop them explicitly (`DROP TABLE ...`) — never `DROP DATABASE petclinic` while services run.

> **Status:** Live verification (steps 1–4) runs as part of PETPLAT-26 after the dev apply; schema scripts were read and table/FK mapping verified against the application repo on 2026-10-14.

