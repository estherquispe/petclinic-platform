# Input variables for the eks module (technical-spec.md → Terraform Modules).

variable "project" {
  description = "Project name used for naming and tagging."
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "Deployment environment (dev or prod)."
  type        = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "environment must be \"dev\" or \"prod\"."
  }
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS cluster and node group."
  type        = string
  default     = "1.36"

  validation {
    condition     = can(regex("^1\\.[0-9]+$", var.cluster_version))
    error_message = "cluster_version must be a Kubernetes version like \"1.36\"."
  }
}

variable "subnet_ids" {
  description = "Subnet IDs for the control plane and node group (public subnets from the VPC module)."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least 2 subnets across 2 AZs."
  }
}

variable "cluster_sg_id" {
  description = "Baseline EKS cluster security group ID (VPC module output)."
  type        = string
}

variable "node_sg_id" {
  description = "Baseline EKS node security group ID (VPC module output)."
  type        = string
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group (t4g = Graviton free trial)."
  type        = list(string)
  default     = ["t4g.small"]
}

variable "node_ami_type" {
  description = "AMI type for the managed node group (AL2023 ARM64 for Kubernetes 1.33+)."
  type        = string
  default     = "AL2023_ARM_64_STANDARD"
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 4
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_disk_size" {
  description = "Root volume size for worker nodes in GB (20 GB fits the 30 GB EBS free tier)."
  type        = number
  default     = 20
}

variable "node_taints" {
  description = "Optional taints for the managed node group."
  type = list(object({
    key    = string
    value  = string
    effect = string
  }))
  default = []

  validation {
    condition = alltrue([
      for t in var.node_taints : contains(["NoSchedule", "PreferNoSchedule", "NoExecute"], t.effect)
    ])
    error_message = "taint effect must be NoSchedule, PreferNoSchedule, or NoExecute."
  }
}

variable "api_server_public_access_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API server endpoint. Restrict from 0.0.0.0/0 where your network allows."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "admin_principal_arns" {
  description = "IAM principals (users/roles) granted cluster admin via EKS access entries. STS session ARNs are rejected — EKS does not accept them (AWS API: 'You can't use the STS session principal type with access entries')."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.admin_principal_arns : !startswith(arn, "arn:aws:sts::")])
    error_message = "admin_principal_arns must be IAM user/role ARNs (arn:aws:iam::...). STS session ARNs (arn:aws:sts::...:assumed-role/...) are rejected by EKS access entries — derive the role ARN with: aws sts get-caller-identity, then set the IAM role ARN."
  }
}

variable "addon_versions" {
  description = "Pinned EKS managed add-on versions (never \"latest\"). Query valid versions with: aws eks describe-addon-versions --kubernetes-version <ver> --addon-name <name>. Upgrade procedure: docs/runbooks/eks-access-and-addons.md"
  type        = map(string)
  default = {
    coredns            = "v1.14.7-eksbuild.10"
    kube-proxy         = "v1.36.0-eksbuild.21"
    vpc-cni            = "v1.23.1-eksbuild.1"
    aws-ebs-csi-driver = "v1.61.1-eksbuild.1"
  }

  validation {
    condition = alltrue([
      for key in ["coredns", "kube-proxy", "vpc-cni", "aws-ebs-csi-driver"] :
      contains(keys(var.addon_versions), key)
    ])
    error_message = "addon_versions must define coredns, kube-proxy, vpc-cni, and aws-ebs-csi-driver."
  }

  validation {
    condition     = alltrue([for v in values(var.addon_versions) : v != "" && v != "latest"])
    error_message = "add-on versions must be explicit pins — \"latest\" is not allowed."
  }
}

variable "tags" {
  description = "Additional tags merged into all resources."
  type        = map(string)
  default     = {}
}
