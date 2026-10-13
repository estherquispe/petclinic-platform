# Petclinic Platform — AWS Infrastructure

Production AWS infrastructure for [Spring Petclinic Microservices](https://github.com/spring-petclinic/spring-petclinic-microservices) (8 services, Spring Boot, Spring Cloud).

## Repository Structure

```
petclinic-platform/
│
├── terraform/                    # Infrastructure as Code
│   ├── environments/
│   │   ├── dev/                  # Dev environment root module
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── outputs.tf
│   │   │   ├── backend.tf        # S3 state: petclinic/dev/terraform.tfstate
│   │   │   └── terraform.tfvars
│   │   └── prod/                 # Prod environment root module
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       ├── outputs.tf
│   │       ├── backend.tf        # S3 state: petclinic/prod/terraform.tfstate
│   │       └── terraform.tfvars
│   └── modules/                  # Reusable modules
│       ├── vpc/                  # VPC, subnets, IGW, security groups (all-public, no NAT)
│       ├── eks/                  # EKS cluster, node groups, OIDC, IAM
│       ├── ecr/                  # ECR repos (per service per env), lifecycle policies
│       ├── rds/                  # RDS MySQL, subnet group, parameter group
│       ├── dns/                  # Route 53, ACM certificates
│       ├── secrets/              # Secrets Manager resources
│       └── observability/        # Prometheus, Grafana, CloudWatch, FluentBit
│
├── k8s/                          # Kubernetes Manifests
│   ├── base/                     # Base manifests (shared across envs)
│   │   ├── namespaces.yaml
│   │   ├── config-server/        # Deployment, Service, ConfigMap
│   │   ├── discovery-server/
│   │   ├── api-gateway/
│   │   ├── customers-service/
│   │   ├── visits-service/
│   │   ├── vets-service/
│   │   ├── genai-service/
│   │   ├── admin-server/
│   │   ├── ingress/              # ALB Ingress Controller config
│   │   └── external-secrets/     # ExternalSecret resources (AWS Secrets Manager)
│   └── overlays/                 # Environment-specific patches
│       ├── dev/                  # Dev: fewer replicas, smaller resources
│       └── prod/                 # Prod: more replicas, larger resources, HPA
│
├── helm/                            # Helm Charts
│   └── petclinic-service/           # Generic chart (shared by all 8 services)
│
├── helm-values/                     # Per-service YAML + per-env (dev.yaml, prod.yaml)
│
├── .github/workflows/            # CI (GitHub Actions — ArgoCD handles CD)
│   ├── build-push.yml            # Build images, push to ECR
│   └── update-image-tags.yml     # Commit image tag updates → ArgoCD deploys
│
├── scripts/                      # Operational scripts
│   ├── bootstrap-state.sh        # Create S3 bucket + DynamoDB for TF state
│   ├── ecr-login.sh              # ECR authentication helper
│   └── build-push-images.sh      # Build 8 ARM64 images (buildx) + push to ECR
│
└── docs/                         # Operational Documentation
    ├── architecture.md           # Infrastructure architecture & diagrams
    ├── runbook.md                # Day-2 operations (restart, scale, rollback)
    ├── incident-playbook.md      # Common failures & fixes
    ├── onboarding.md             # New engineer setup guide
    └── adr/                      # Architecture Decision Records
        └── 0001-public-subnets.md  # All-public subnet design decision
```

## Tech Stack

| Layer | Tool | Details |
|-------|------|---------|
| Cloud | AWS | us-east-1 |
| IaC | Terraform >= 1.6 | AWS provider ~> 5.0, S3 + DynamoDB state |
| Cluster | Amazon EKS | Managed node groups, OIDC |
| Registry | Amazon ECR | One repo per service per env, lifecycle policies, scan-on-push |
| Database | Amazon RDS MySQL | Single-AZ both envs (cost optimization) |
| DNS | Route 53 + ACM | TLS termination at ALB |
| Secrets | AWS Secrets Manager | External Secrets Operator in K8s |
| Ingress | AWS ALB Ingress Controller | Public ALB → API Gateway service |
| Observability | Prometheus + Grafana | Micrometer metrics, dashboards, alerts |
| Logging | FluentBit + CloudWatch | Centralized log aggregation |
| Tracing | Zipkin | Distributed tracing (OpenTelemetry) |
| CI | GitHub Actions | OIDC → AWS, build → push ECR → commit image tag |
| CD | ArgoCD | GitOps — watches Git, auto-sync (dev), manual sync (prod) |
| Packaging | Helm | Generic chart, per-service + per-env values |
| Node Scaling | Karpenter | NodePools, EC2NodeClass, Spot diversification |

## Build & Push Images (initial manual build)

Before the first deployment, build all 8 images for **linux/arm64** (required for
the t4g Graviton nodes) and push them to ECR. Maven builds the JARs only —
image creation is done with `docker buildx`, **not** the Maven `buildDocker`
profile (PETPLAT-85).

```bash
# One-shot: builds JARs → logs into ECR → builds ARM64 images → pushes → verifies
./scripts/build-push-images.sh                      # petclinic-dev, tag v1.0.0
./scripts/build-push-images.sh --tag a1b2c3d        # short commit SHA tag

# Equivalent manual commands
cd ../spring-petclinic-microservices && ./mvnw clean package -DskipTests   # JARs only
./scripts/ecr-login.sh --region us-east-1                                  # ECR auth
docker buildx build --platform linux/arm64 \
  --build-arg ARTIFACT_NAME=spring-petclinic-config-server-<version> \
  --build-arg EXPOSED_PORT=8888 \
  -f ../spring-petclinic-microservices/docker/Dockerfile \
  -t {account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-dev/config-server:v1.0.0 \
  --push ../spring-petclinic-microservices/spring-petclinic-config-server/target
```

Image URIs follow `{account}.dkr.ecr.us-east-1.amazonaws.com/petclinic-{env}/{service}:{tag}`.
Never use the `latest` tag — use `v1.0.0` for initial pushes or the 7-char commit SHA in CI.

## Environments

| Environment | K8s Namespace | RDS | Purpose |
|-------------|---------------|-----|---------|
| dev | `petclinic-dev` | db.t4g.micro, single-AZ (free tier) | Development & testing |
| prod | `petclinic-prod` | db.t4g.micro, single-AZ (free tier) | Production |
