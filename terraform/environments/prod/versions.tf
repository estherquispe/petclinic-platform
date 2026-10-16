# Version constraints for the prod environment root module.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.100.0, < 6.0.0" # floor per eks/dns modules (access entries, node_repair_config)
    }
  }
}
