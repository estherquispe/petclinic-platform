# Runbook: EKS Access & Add-on Upgrades

Covers two operational procedures:

1. **How to add additional users/roles to the cluster** (PETPLAT-14)
2. **How to upgrade EKS add-on versions** (PETPLAT-84)

---

## 1. Cluster access (EKS access entries)

Access is managed entirely in Terraform. The cluster is created with
`authentication_mode = API_AND_CONFIG_MAP` and
`bootstrap_cluster_creator_admin_permissions = false`, so **nobody has
Kubernetes access unless an access entry grants it**.

### How the deployer gets access

`terraform/environments/{dev,prod}/main.tf` passes the deploying principal to
the module:

```hcl
admin_principal_arns = length(var.eks_admin_principal_arns) > 0 ? var.eks_admin_principal_arns : [data.aws_caller_identity.current.arn]
```

After `terraform apply`, configure kubectl with the module output:

```bash
terraform output -raw kubeconfig_update_command
# → aws eks update-kubeconfig --name petclinic-dev --region us-east-1
kubectl get nodes
```

### Adding another user or role

1. Get the IAM principal ARN (must be an IAM **user** or **role** — never an
   STS session ARN such as `arn:aws:sts::...:assumed-role/...`):

   ```bash
   # for a role
   aws iam get-role --role-name my-dev-role --query Role.Arn --output text
   # for a user
   aws iam get-user --user-name alice --query User.Arn --output text
   ```

2. Add the ARN to `eks_admin_principal_arns` in `terraform.tfvars` of the
   target environment (or set the variable at apply time):

   ```hcl
   eks_admin_principal_arns = [
     "arn:aws:iam::111122223333:role/my-dev-role",
   ]
   ```

3. Plan, review, and apply. Terraform creates an `aws_eks_access_entry` plus
   an `aws_eks_access_policy_association` granting
   `AmazonEKSClusterAdminPolicy` at cluster scope.

4. The new user configures their own kubeconfig:

   ```bash
   aws eks update-kubeconfig --name petclinic-dev --region us-east-1
   ```

> **Note:** If you deploy with an assumed-role/SSO session and the apply fails
> with an "invalid principal" error on the access entry, the caller identity is
> an STS session ARN. Set `eks_admin_principal_arns` explicitly to the IAM role
> ARN instead of relying on the default.

### Removing access

Delete the ARN from `eks_admin_principal_arns` and apply — the entry and policy
association are destroyed together.

### Restricting the public API server endpoint (recommended)

The Kubernetes API endpoint is public (spec requirement) but should be
CIDR-restricted to the networks you deploy and debug from. In
`terraform.tfvars` of the target environment:

```hcl
api_server_public_access_cidrs = ["203.0.113.10/32"]  # your public IP/32
```

If you leave the default `0.0.0.0/0`, anyone on the internet can *reach* the
API server (authentication still applies, but exposure is needlessly broad).
Update the CIDR whenever your network changes — the endpoint stays public, only
the allowed source list changes.

---

## 2. Upgrading EKS add-on versions

Add-on versions are **pinned** in the `addon_versions` map of
`terraform/modules/eks/variables.tf` — never `latest`, so upgrades are always a
deliberate, reviewed change.

### Current pins (Kubernetes 1.36)

| Add-on | Variable key | Pinned version |
|--------|--------------|----------------|
| CoreDNS | `coredns` | `v1.14.7-eksbuild.10` |
| kube-proxy | `kube-proxy` | `v1.36.0-eksbuild.21` |
| VPC CNI | `vpc-cni` | `v1.23.1-eksbuild.1` |
| EBS CSI Driver | `aws-ebs-csi-driver` | `v1.61.1-eksbuild.1` |

### Procedure

1. List the versions available for your cluster version:

   ```bash
   aws eks describe-addon-versions \
     --kubernetes-version 1.36 \
     --addon-name coredns \
     --query 'addons[].addonVersions[].addonVersion' --output text
   ```

   Repeat for `kube-proxy`, `vpc-cni`, and `aws-ebs-csi-driver`.

2. Edit the `addon_versions` default map in
   `terraform/modules/eks/variables.tf` (or override it at the module call)
   with the new pins.

3. Plan and review the diff — only `aws_eks_addon.*` should change:

   ```bash
   terraform plan -out plan.out
   terraform apply plan.out
   ```

4. Verify the add-ons are healthy:

   ```bash
   aws eks describe-add-ons --cluster-name petclinic-dev \
     --query 'add-ons[].[addonName,addonVersion,status]' --output table
   kubectl get pods -n kube-system
   ```

### When to upgrade

- **After a cluster version upgrade** — add-ons must support the new
  Kubernetes version; upgrade them in the same change window.
- **Security patches** — check the AWS EKS add-on release notes regularly.
- One add-on upgrade per PR keeps the blast radius small and the plan easy to
  review.

> The `resolve_conflicts_on_create/update = "OVERWRITE"` strategy is set for
> initial setup as required by the spec. Over time, prefer editing add-on
> configuration through Terraform so OVERWRITE does not silently revert manual
> `kubectl edit` changes.
