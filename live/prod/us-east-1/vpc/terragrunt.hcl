include "root" {
  path = find_in_parent_folders()
}

terraform {
  source = "git::https://github.com/beravelli/tf-module-vpc.git?ref=v1.0.0"
}

inputs = {
  vpc_cidr             = "10.20.0.0/16"
  availability_zones   = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnet_cidrs = ["10.20.1.0/24", "10.20.2.0/24", "10.20.3.0/24"]
  public_subnet_cidrs  = ["10.20.101.0/24", "10.20.102.0/24", "10.20.103.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = false
  tags = { Environment = "prod", ManagedBy = "terragrunt" }
}
