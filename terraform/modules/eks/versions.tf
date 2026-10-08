# Version constraints for the eks module.
#
# Floor is 5.100.0 (the version pinned in the environment lockfiles): the
# module uses aws_eks_access_entry / aws_eks_access_policy_association and
# node_repair_config, which older 5.x releases do not all provide.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.100.0, < 6.0.0"
    }
  }
}