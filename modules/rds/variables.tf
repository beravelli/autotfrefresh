variable "env"               { type = string }
variable "identifier"        { type = string }
variable "engine"            { type = string; default = "postgres" }
variable "engine_version"    { type = string; default = "16.2" }
variable "instance_class"    { type = string }
variable "allocated_storage" { type = number; default = 20 }
variable "db_name"           { type = string }
variable "vpc_id"            { type = string }
variable "subnet_ids"        { type = list(string) }
variable "multi_az"          { type = bool; default = false }
variable "tags"              { type = map(string); default = {} }
