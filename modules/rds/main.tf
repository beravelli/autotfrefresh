# RDS module stub — sufficient for tofu validate.

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  db_full_name = "${var.env}-${var.identifier}"
}

output "db_identifier" { value = local.db_full_name }
output "db_endpoint"   { value = "stub.rds.example.com" }
