locals {
  name     = "credify-5-prod"
  vpc_cidr = "10.105.0.0/16"
  apps     = var.phase != "foundation"
  replica  = contains(["replica", "tuned"], var.phase)
  tuned    = var.phase == "tuned"
  tags = {
    Environment        = "production"
    Application        = "shared"
    CostCentre         = "platform"
    BusinessUnit       = "technology"
    Owner              = var.owner
    DataClassification = "internal"
    StudentNumber      = "5"
    Group              = "A"
  }
  service_sizes = {
    api = { cpu = 1024, memory = 2048, port = 3000 }
    lms = { cpu = 1024, memory = 2048, port = 4000 }
    erp = { cpu = 1024, memory = 2048, port = 8069 }
  }
  databases = {
    core  = { engine = "postgres", version = "16", family = "postgres16", class = "db.t4g.medium", storage = 50, port = 5432 }
    erpdb = { engine = "postgres", version = "16", family = "postgres16", class = "db.t4g.small", storage = 20, port = 5432 }
    maria = { engine = "mariadb", version = "10.11", family = "mariadb10.11", class = "db.t4g.small", storage = 20, port = 3306 }
  }
}
resource "terraform_data" "guardrails" {
  input = var.phase
  lifecycle {
    precondition {
      condition     = var.lab_settings_confirmed
      error_message = "Confirm the reviewed lab settings before creating paid resources."
    }
    precondition {
      condition     = !local.replica || var.baseline_recorded
      error_message = "Save the untuned baseline before creating the reporting replica."
    }
    precondition {
      condition     = !local.tuned || (var.baseline_recorded && var.tuning_completed)
      error_message = "Run tune.py successfully before enabling tuned application settings."
    }
    precondition {
      condition     = alltrue([for s in local.service_sizes : s.cpu <= 2048 && s.memory <= 4096])
      error_message = "Fargate task sizes exceed the manual ceiling."
    }
    precondition {
      condition     = local.databases.core.storage >= 50 && local.databases.core.storage <= 100 && local.databases.maria.storage == 20
      error_message = "Core storage must stay at 50-100 GiB and MariaDB at 20 GiB."
    }
    precondition {
      condition     = alltrue([for k in ["core", "erpdb"] : contains(["db.t4g.micro", "db.t4g.small", "db.t4g.medium"], local.databases[k].class)]) && local.databases.maria.class == "db.t4g.small"
      error_message = "RDS classes exceed the manual ceilings."
    }
  }
}
data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" { state = "available" }
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}
