# Root terragrunt.hcl — inherited by all stacks via find_in_parent_folders()
#
# Uses a LOCAL backend for testing (no S3 / DynamoDB required).
# Switch to remote_state { backend = "s3" ... } for production.

locals {
  path_parts = split("/", path_relative_to_include())
  env        = local.path_parts[0]   # dev | prod
  region     = local.path_parts[1]   # us-east-1

  env_vars   = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  account_id = local.env_vars.locals.aws_account_id
}

# ── Local backend (testing) ──────────────────────────────────────────────────
remote_state {
  backend = "local"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    path = "${get_repo_root()}/.terraform-state/${path_relative_to_include()}/terraform.tfstate"
  }
}

# ── Provider ─────────────────────────────────────────────────────────────────
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_version = ">= 1.6.0"
      required_providers {
        aws = {
          source  = "hashicorp/aws"
          version = "~> 5.0"
        }
      }
    }
    provider "aws" {
      region = "${local.region}"
    }
  EOF
}

inputs = {
  env    = local.env
  region = local.region
}
