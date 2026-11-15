resource "random_password" "credential" {
  for_each = toset(["core-admin", "erp-admin", "maria-admin", "api-db", "erp-db", "lms-db", "odoo-admin"])
  length   = 32
  special  = false
}
locals {
  users = {
    core-admin = "credify_admin", erp-admin = "credify_admin", maria-admin = "credify_admin",
    api-db     = "credify_api", erp-db = "credify_erp", lms-db = "credify_lms", odoo-admin = "odoo_master"
  }
  admin_secret_key = { core = "core-admin", erpdb = "erp-admin", maria = "maria-admin" }
}
# Ordinary Secrets Manager secrets. RDS-managed core credentials would block replica creation.
# Passwords exist in Terraform state: protect it; never commit/upload state or plan files.
resource "aws_secretsmanager_secret" "credential" {
  for_each                = local.users
  name                    = "${local.name}/${each.key}"
  recovery_window_in_days = 7
  tags                    = { Name = "${local.name}-${each.key}" }
}
resource "aws_secretsmanager_secret_version" "credential" {
  for_each  = local.users
  secret_id = aws_secretsmanager_secret.credential[each.key].id
  secret_string = jsonencode({
    username = each.value
    password = random_password.credential[each.key].result
  })
}
resource "aws_db_subnet_group" "data" {
  name       = "${local.name}-data"
  subnet_ids = [aws_subnet.lab["data_a"].id, aws_subnet.lab["data_b"].id]
  tags       = { Name = "${local.name}-data" }
}
resource "aws_db_parameter_group" "lab" {
  for_each = local.databases
  name     = "${local.name}-${each.key}"
  family   = each.value.family
  parameter {
    name         = each.value.engine == "postgres" ? "rds.force_ssl" : "require_secure_transport"
    value        = "1"
    apply_method = "pending-reboot"
  }
}
resource "aws_db_instance" "primary" {
  for_each                     = local.databases
  identifier                   = "${local.name}-${each.key}"
  engine                       = each.value.engine
  engine_version               = each.value.version
  instance_class               = each.value.class
  allocated_storage            = each.value.storage
  max_allocated_storage        = 0
  storage_type                 = "gp3"
  storage_encrypted            = true
  username                     = "credify_admin"
  password                     = random_password.credential[local.admin_secret_key[each.key]].result
  db_name                      = each.key == "core" ? "credify_core" : null
  port                         = each.value.port
  db_subnet_group_name         = aws_db_subnet_group.data.name
  parameter_group_name         = aws_db_parameter_group.lab[each.key].name
  vpc_security_group_ids       = [aws_security_group.lab[each.key].id]
  publicly_accessible          = false
  multi_az                     = false
  availability_zone            = data.aws_availability_zones.available.names[0]
  backup_retention_period      = 1
  backup_window                = "01:00-01:30"
  maintenance_window           = "sun:02:00-sun:03:00"
  copy_tags_to_snapshot        = true
  auto_minor_version_upgrade   = true
  deletion_protection          = !var.allow_lab_data_deletion
  skip_final_snapshot          = true
  delete_automated_backups     = true
  performance_insights_enabled = false
  monitoring_interval          = 0
  apply_immediately            = true
  tags = {
    Name         = "${local.name}-${each.key}"
    Application  = each.key == "core" ? "api" : (each.key == "erpdb" ? "erp" : "lms")
    CostCentre   = each.key == "erpdb" ? "erp" : "lending"
    BusinessUnit = each.key == "erpdb" ? "finance" : "lending"
  }
  depends_on = [terraform_data.guardrails]
}
resource "aws_db_instance" "core_read" {
  count                      = local.replica ? 1 : 0
  identifier                 = "${local.name}-core-ro"
  replicate_source_db        = aws_db_instance.primary["core"].identifier
  instance_class             = "db.t4g.medium"
  allocated_storage          = 50
  max_allocated_storage      = 0
  storage_type               = "gp3"
  storage_encrypted          = true
  parameter_group_name       = aws_db_parameter_group.lab["core"].name
  vpc_security_group_ids     = [aws_security_group.lab["core"].id]
  publicly_accessible        = false
  multi_az                   = false
  availability_zone          = data.aws_availability_zones.available.names[1]
  backup_retention_period    = 0
  deletion_protection        = !var.allow_lab_data_deletion
  skip_final_snapshot        = true
  delete_automated_backups   = true
  auto_minor_version_upgrade = true
  apply_immediately          = true
  tags                       = { Name = "${local.name}-core-ro", Application = "api", CostCentre = "lending", BusinessUnit = "lending" }
  depends_on                 = [terraform_data.guardrails]
}
