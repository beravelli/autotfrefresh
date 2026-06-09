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
  source = "git::https://github.com/beravelli/autotfrefresh.git//modules/rds?ref=rds/v1.0.0"
}

inputs = {
  identifier        = "postgres"
  engine            = "postgres"
  engine_version    = "16.2"
  instance_class    = "db.r6g.large"
  allocated_storage = 100
  db_name           = "appdb"
  vpc_id            = dependency.vpc.outputs.vpc_id
  subnet_ids        = dependency.vpc.outputs.private_subnet_ids
  multi_az          = true
  tags = { Environment = "prod", ManagedBy = "terragrunt" }
}
