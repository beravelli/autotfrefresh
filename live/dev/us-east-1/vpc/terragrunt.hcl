include "root" {
  path = find_in_parent_folders()
}

terraform {
  # Source: monorepo subdirectory. Tag format: vpc/v<semver>
  # The refresh pipeline patches this ref when a new vpc tag is pushed.
  source = "git::https://github.com/beravelli/autotfrefresh.git//modules/vpc?ref=vpc/v1.0.0"
}

inputs = {
  vpc_cidr             = "10.10.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnet_cidrs = ["10.10.1.0/24", "10.10.2.0/24", "10.10.3.0/24"]
  public_subnet_cidrs  = ["10.10.101.0/24", "10.10.102.0/24", "10.10.103.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  tags = { Environment = "dev", ManagedBy = "terragrunt" }
}
