# Mock providers: these tests do not contact AWS or provision resources.
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["af-south-1a", "af-south-1b", "af-south-1c"] }
  }
  mock_data "aws_caller_identity" { defaults = { account_id = "123456789012" } }
  mock_data "aws_ami" { defaults = { id = "ami-0123456789abcdef0" } }
  mock_data "aws_ec2_managed_prefix_list" { defaults = { id = "pl-0123456789abcdef0" } }
  mock_data "aws_cloudfront_cache_policy" { defaults = { id = "413f1604-38af-4f4b-8d49-1d74519c7733" } }
  mock_data "aws_cloudfront_origin_request_policy" { defaults = { id = "216adef6-5c7f-47e4-b989-5492eafa07d3" } }
  mock_data "aws_ecr_image" { defaults = { image_digest = "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" } }
}
mock_provider "aws" { alias = "edge" }
mock_provider "random" {}
mock_provider "archive" {}
variables {
  aws_account_id         = "123456789012"
  owner                  = "student@example.test"
  lab_settings_confirmed = true
}
run "foundation_is_small_and_private" {
  command = plan
  assert {
    condition     = length(aws_db_instance.primary) == 3 && length(aws_db_instance.core_read) == 0 && length(aws_ecs_service.app) == 0 && length(aws_ecs_service.lms) == 0
    error_message = "Foundation must not launch services or a reporting replica."
  }
  assert {
    condition     = alltrue([for db in aws_db_instance.primary : !db.publicly_accessible && !db.multi_az && db.storage_encrypted && db.max_allocated_storage == 0])
    error_message = "Lab databases must be private, encrypted, Single-AZ and have storage autoscaling disabled."
  }
  assert {
    condition     = aws_db_instance.primary["core"].instance_class == "db.t4g.medium" && aws_db_instance.primary["maria"].instance_class == "db.t4g.small" && aws_instance.management.instance_type == "t3.small"
    error_message = "A deployed class exceeds the reviewed lab size."
  }
  assert {
    condition     = length(aws_subnet.lab) == 7 && length(aws_route.private_egress) == 2 && !contains(keys(aws_route.private_egress), "data")
    error_message = "Data subnets must not receive an internet default route."
  }
  assert {
    condition     = aws_vpc.lab.cidr_block == "10.105.0.0/16" && length(aws_wafv2_web_acl.lab) == 0
    error_message = "Use the student's VPC and no unapproved WAF by default."
  }
}
run "baseline_uses_three_small_tasks_without_replica" {
  command = plan
  variables { phase = "baseline" }
  assert {
    condition     = length(aws_ecs_service.app) == 2 && length(aws_ecs_service.lms) == 1 && length(aws_db_instance.core_read) == 0
    error_message = "Baseline must run all services without a replica."
  }
  assert {
    condition     = alltrue([for s in merge(aws_ecs_service.app, aws_ecs_service.lms) : s.desired_count == 1 && s.deployment_maximum_percent <= 200 && !s.network_configuration[0].assign_public_ip])
    error_message = "No public task IPs or more than two tasks including deployment surge."
  }
  assert {
    condition     = local.environments.api.PORTFOLIO_MATVIEW == "false" && !contains(keys(local.environments.api), "READ_DB_HOST")
    error_message = "Baseline must not route reads to a replica or enable the view."
  }
}
run "service_connect_preserves_configuration_and_ceiling" {
  command = plan
  variables { phase = "baseline" }
  assert {
    condition     = alltrue([for t in aws_ecs_task_definition.app : tonumber(t.cpu) <= 2048 && tonumber(t.memory) <= 4096])
    error_message = "Every task including its proxy must stay within 2 vCPU and 4 GiB."
  }
  assert {
    condition     = alltrue([for env in local.environments : length(keys(env)) > 0])
    error_message = "All applications must define environment configuration."
  }
  assert {
    condition     = local.environments.api.LMS_URL == "http://lms:4000"
    error_message = "The API must use the private Service Connect LMS alias."
  }
  assert {
    condition     = one(aws_ecs_service.app["api"].service_connect_configuration).enabled && one(aws_ecs_service.lms["lms"].service_connect_configuration).enabled && length(aws_ecs_service.app["erp"].service_connect_configuration) == 0
    error_message = "Only API and LMS should use Service Connect."
  }
  assert {
    condition     = one(one(one(aws_ecs_service.lms["lms"].service_connect_configuration).service).client_alias).dns_name == "lms"
    error_message = "The LMS endpoint must match the API alias."
  }
}
run "replica_does_not_switch_application_reads_yet" {
  command = plan
  variables {
    phase             = "replica"
    baseline_recorded = true
  }
  assert {
    condition     = length(aws_db_instance.core_read) == 1 && !contains(keys(local.environments.api), "READ_DB_HOST") && local.environments.api.PORTFOLIO_MATVIEW == "false"
    error_message = "Create the replica while preserving the untuned application configuration until SQL is ready."
  }
}
run "tuned_enables_view_and_read_split" {
  command = plan
  variables {
    phase             = "tuned"
    baseline_recorded = true
    tuning_completed  = true
  }
  assert {
    condition     = local.environments.api.PORTFOLIO_MATVIEW == "true" && contains(keys(local.environments.api), "READ_DB_HOST") && length(aws_db_instance.core_read) == 1
    error_message = "Tuned stage must enable the view and exactly one reporting replica."
  }
}
run "block_unconfirmed_lab_settings" {
  command = plan
  variables { lab_settings_confirmed = false }
  expect_failures = [terraform_data.guardrails]
}
run "block_replica_before_baseline" {
  command = plan
  variables { phase = "replica" }
  expect_failures = [terraform_data.guardrails]
}
run "block_view_before_tuning" {
  command = plan
  variables {
    phase             = "tuned"
    baseline_recorded = true
  }
  expect_failures = [terraform_data.guardrails]
}
