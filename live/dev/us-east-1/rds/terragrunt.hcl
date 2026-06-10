include "root" {
  path = find_in_parent_folders()
}

dependency "vpc" {
  config_path = "../vpc"
  mock_outputs = {
    vpc_id             = "vpc-00000000"
    private_subnet_ids = ["subnet-00000001", "subnet-00000002"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan", "init"]
}

terraform {
  source = "git::https://github.com/beravelli/tf-module-rds.git?ref=v1.0.0"
}

inputs = {
  identifier        = "postgres"
  engine            = "postgres"
  engine_version    = "16.2"
  instance_class    = "db.t3.medium"
  allocated_storage = 20
  db_name           = "appdb"
  vpc_id            = dependency.vpc.outputs.vpc_id
  subnet_ids        = dependency.vpc.outputs.private_subnet_ids
  multi_az          = false
  tags = { Environment = "dev", ManagedBy = "terragrunt" }
}
