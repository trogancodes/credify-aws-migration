resource "aws_ecr_repository" "app" {
  for_each             = local.service_sizes
  name                 = "${local.name}-${each.key}"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = var.allow_lab_data_deletion
  image_scanning_configuration { scan_on_push = true }
  tags = { Application = each.key }
}
data "aws_ecr_image" "app" {
  for_each        = local.apps ? local.service_sizes : {}
  repository_name = aws_ecr_repository.app[each.key].name
  image_tag       = var.image_tag
}
resource "aws_cloudwatch_log_group" "app" {
  for_each          = local.service_sizes
  name              = "/ecs/${local.name}-${each.key}"
  retention_in_days = 7
  tags              = { Application = each.key }
}
resource "aws_ecs_cluster" "lab" {
  name = local.name
  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}
resource "aws_service_discovery_http_namespace" "lab" {
  name        = "${local.name}.internal"
  description = "Private API-to-LMS discovery through ECS Service Connect"
}
locals {
  environments = {
    api = merge({
      PORT        = "3000", DB_HOST = aws_db_instance.primary["core"].address,
      DB_PORT     = "5432", DB_NAME = "credify_core", DB_USER = "credify_api",
      DB_SSL      = "true", DB_POOL = "10", PORTFOLIO_MATVIEW = tostring(local.tuned),
      LMS_URL     = "http://lms:4000",
      CORS_ORIGIN = "https://${aws_cloudfront_distribution.lab.domain_name}"
    }, local.tuned ? { READ_DB_HOST = aws_db_instance.core_read[0].address } : {})
    lms = {
      PORT     = "4000", MDB_HOST = aws_db_instance.primary["maria"].address,
      MDB_PORT = "3306", MDB_NAME = "credify_lms", MDB_USER = "credify_lms"
    }
    erp = {
      HOST         = aws_db_instance.primary["erpdb"].address, PORT = "5432", USER = "credify_erp",
      ODOO_LIST_DB = var.odoo_initialized ? "False" : "True"
    }
  }
  injected_secrets = {
    api = [{ name = "DB_PASSWORD", valueFrom = "${aws_secretsmanager_secret.credential["api-db"].arn}:password::" }]
    lms = [{ name = "MDB_PASSWORD", valueFrom = "${aws_secretsmanager_secret.credential["lms-db"].arn}:password::" }]
    erp = [
      { name = "PASSWORD", valueFrom = "${aws_secretsmanager_secret.credential["erp-db"].arn}:password::" },
      { name = "ODOO_MASTER_PASSWORD", valueFrom = "${aws_secretsmanager_secret.credential["odoo-admin"].arn}:password::" }
    ]
  }
}
resource "aws_ecs_task_definition" "app" {
  for_each                 = local.apps ? local.service_sizes : {}
  family                   = "${local.name}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(each.value.cpu)
  memory                   = tostring(each.value.memory)
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task[each.key].arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  dynamic "volume" {
    for_each = each.key == "erp" ? [1] : []
    content {
      name = "odoo-data"
      efs_volume_configuration {
        file_system_id     = aws_efs_file_system.odoo.id
        transit_encryption = "ENABLED"
        root_directory     = "/"
        authorization_config {
          access_point_id = aws_efs_access_point.odoo.id
          iam             = "ENABLED"
        }
      }
    }
  }
  container_definitions = jsonencode([merge({
    name  = each.key, essential = true,
    image = "${aws_ecr_repository.app[each.key].repository_url}@${data.aws_ecr_image.app[each.key].image_digest}",
    portMappings = [{
      name          = each.key
      containerPort = each.value.port
      protocol      = "tcp"
    }],
    environment = [for k, v in local.environments[each.key] : { name = k, value = v }],
    secrets     = local.injected_secrets[each.key],
    logConfiguration = {
      logDriver = "awslogs",
      options   = { awslogs-group = aws_cloudwatch_log_group.app[each.key].name, awslogs-region = var.region, awslogs-stream-prefix = "ecs" }
    }
    }, each.key == "erp" ? {
    mountPoints = [{ sourceVolume = "odoo-data", containerPath = "/var/lib/odoo", readOnly = false }]
    } : {}, each.key == "erp" ? {} : {
    healthCheck = {
      command  = ["CMD-SHELL", "node -e \"fetch('http://127.0.0.1:${each.value.port}/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))\""],
      interval = 30, timeout = 10, retries = 5, startPeriod = 60
    }
  })])
  tags = { Application = each.key }
}
# LMS is created first so its Service Connect endpoint exists before API startup.
resource "aws_ecs_service" "lms" {
  for_each                           = { for k, v in local.service_sizes : k => v if local.apps && k == "lms" }
  name                               = "${local.name}-${each.key}"
  cluster                            = aws_ecs_cluster.lab.id
  task_definition                    = aws_ecs_task_definition.app[each.key].arn
  desired_count                      = 1
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  deployment_minimum_healthy_percent = each.key == "erp" ? 0 : 100
  deployment_maximum_percent         = each.key == "erp" ? 100 : 200
  health_check_grace_period_seconds  = each.key == "lms" ? null : 180
  wait_for_steady_state              = true
  enable_ecs_managed_tags            = true
  propagate_tags                     = "SERVICE"
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = [aws_subnet.lab["app_a"].id, aws_subnet.lab["app_b"].id]
    assign_public_ip = false
    security_groups  = [aws_security_group.lab[each.key].id]
  }
  dynamic "load_balancer" {
    for_each = each.key == "lms" ? [] : [each.key]
    content {
      target_group_arn = aws_lb_target_group.app[each.key].arn
      container_name   = each.key
      container_port   = each.value.port
    }
  }
  dynamic "service_connect_configuration" {
    for_each = each.key == "erp" ? [] : [1]

    content {
      enabled   = true
      namespace = aws_service_discovery_http_namespace.lab.arn

      log_configuration {
        log_driver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app[each.key].name
          awslogs-region        = var.region
          awslogs-stream-prefix = "service-connect"
        }
      }

      dynamic "service" {
        for_each = each.key == "lms" ? [1] : []

        content {
          port_name      = "lms"
          discovery_name = "lms"

          client_alias {
            dns_name = "lms"
            port     = 4000
          }
        }
      }
    }
  }
  tags = {
    Application  = each.key
    CostCentre   = each.key == "erp" ? "erp" : "lending"
    BusinessUnit = each.key == "erp" ? "finance" : "lending"
  }
  depends_on = [
    aws_lb_listener.http, aws_lb_listener_rule.api,
    aws_iam_role_policy_attachment.execution, aws_iam_role_policy.execution_secrets,
    aws_iam_role_policy.efs, aws_efs_file_system_policy.odoo, aws_efs_mount_target.odoo,
    aws_route.private_egress, aws_secretsmanager_secret_version.credential,
    aws_vpc_security_group_ingress_rule.connection, aws_vpc_security_group_egress_rule.connection
  ]
}

resource "aws_ecs_service" "app" {
  for_each                           = { for k, v in local.service_sizes : k => v if local.apps && k != "lms" }
  name                               = "${local.name}-${each.key}"
  cluster                            = aws_ecs_cluster.lab.id
  task_definition                    = aws_ecs_task_definition.app[each.key].arn
  desired_count                      = 1
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  deployment_minimum_healthy_percent = each.key == "erp" ? 0 : 100
  deployment_maximum_percent         = each.key == "erp" ? 100 : 200
  health_check_grace_period_seconds  = each.key == "lms" ? null : 180
  wait_for_steady_state              = true
  enable_ecs_managed_tags            = true
  propagate_tags                     = "SERVICE"
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = [aws_subnet.lab["app_a"].id, aws_subnet.lab["app_b"].id]
    assign_public_ip = false
    security_groups  = [aws_security_group.lab[each.key].id]
  }
  dynamic "load_balancer" {
    for_each = each.key == "lms" ? [] : [each.key]
    content {
      target_group_arn = aws_lb_target_group.app[each.key].arn
      container_name   = each.key
      container_port   = each.value.port
    }
  }
  dynamic "service_connect_configuration" {
    for_each = each.key == "erp" ? [] : [1]

    content {
      enabled   = true
      namespace = aws_service_discovery_http_namespace.lab.arn

      log_configuration {
        log_driver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.app[each.key].name
          awslogs-region        = var.region
          awslogs-stream-prefix = "service-connect"
        }
      }

      dynamic "service" {
        for_each = each.key == "lms" ? [1] : []

        content {
          port_name      = "lms"
          discovery_name = "lms"

          client_alias {
            dns_name = "lms"
            port     = 4000
          }
        }
      }
    }
  }
  tags = {
    Application  = each.key
    CostCentre   = each.key == "erp" ? "erp" : "lending"
    BusinessUnit = each.key == "erp" ? "finance" : "lending"
  }
  depends_on = [
    aws_ecs_service.lms,
    aws_lb_listener.http, aws_lb_listener_rule.api,
    aws_iam_role_policy_attachment.execution, aws_iam_role_policy.execution_secrets,
    aws_iam_role_policy.efs, aws_efs_file_system_policy.odoo, aws_efs_mount_target.odoo,
    aws_route.private_egress, aws_secretsmanager_secret_version.credential,
    aws_vpc_security_group_ingress_rule.connection, aws_vpc_security_group_egress_rule.connection
  ]
}
