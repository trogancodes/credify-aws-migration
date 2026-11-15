resource "random_id" "suffix" { byte_length = 3 }
resource "aws_s3_bucket" "lab" {
  bucket        = "${local.name}-${var.aws_account_id}-${random_id.suffix.hex}"
  force_destroy = var.allow_lab_data_deletion
  tags          = { Name = "${local.name}-storage" }
  depends_on    = [terraform_data.guardrails]
}
resource "aws_s3_bucket_public_access_block" "lab" {
  bucket                  = aws_s3_bucket.lab.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_ownership_controls" "lab" {
  bucket = aws_s3_bucket.lab.id
  rule { object_ownership = "BucketOwnerEnforced" }
}
resource "aws_s3_bucket_versioning" "lab" {
  bucket = aws_s3_bucket.lab.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "lab" {
  bucket = aws_s3_bucket.lab.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_lifecycle_configuration" "documents" {
  bucket = aws_s3_bucket.lab.id
  rule {
    id     = "documents-after-90-days"
    status = "Enabled"
    filter { prefix = "documents/" }
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}
resource "aws_s3_object" "frontend" {
  for_each     = toset(["index.html", "config.js"])
  bucket       = aws_s3_bucket.lab.id
  key          = "frontend/${each.key}"
  source       = "${path.module}/../payload/credify-starter-kit/frontend/${each.key}"
  source_hash  = filemd5("${path.module}/../payload/credify-starter-kit/frontend/${each.key}")
  content_type = each.key == "index.html" ? "text/html" : "application/javascript"
  tags         = { Application = "frontend" }
}
resource "aws_s3_object" "document_example" {
  bucket       = aws_s3_bucket.lab.id
  key          = "documents/demo.txt"
  content      = "Credify student 5: fictional lab document. No customer data.\n"
  content_type = "text/plain"
}
data "archive_file" "payload" {
  type        = "zip"
  source_dir  = "${path.module}/../payload"
  output_path = "${path.module}/.build/lab-payload.zip"
}
resource "aws_s3_object" "bootstrap" {
  bucket      = aws_s3_bucket.lab.id
  key         = "bootstrap/lab-payload.zip"
  source      = data.archive_file.payload.output_path
  source_hash = data.archive_file.payload.output_base64sha256
}
resource "aws_s3_object" "config" {
  bucket       = aws_s3_bucket.lab.id
  key          = "bootstrap/lab-config.json"
  content_type = "application/json"
  content = jsonencode({
    region    = var.region
    name      = local.name
    bucket    = aws_s3_bucket.lab.id
    alb_name  = aws_lb.lab.name
    alb_dns   = aws_lb.lab.dns_name
    vpc_id    = aws_vpc.lab.id
    endpoints = { for k, db in aws_db_instance.primary : k => db.address }
    secrets   = { for k, s in aws_secretsmanager_secret.credential : k => s.arn }
  })
}
resource "aws_efs_file_system" "odoo" {
  creation_token   = "${local.name}-odoo"
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"
  tags             = { Name = "${local.name}-odoo", Application = "erp", CostCentre = "erp", BusinessUnit = "finance" }
}
resource "aws_efs_backup_policy" "odoo" {
  file_system_id = aws_efs_file_system.odoo.id
  backup_policy { status = "DISABLED" }
}
resource "aws_efs_mount_target" "odoo" {
  for_each        = toset(["data_a", "data_b"])
  file_system_id  = aws_efs_file_system.odoo.id
  subnet_id       = aws_subnet.lab[each.key].id
  security_groups = [aws_security_group.lab["efs"].id]
}
resource "aws_efs_access_point" "odoo" {
  file_system_id = aws_efs_file_system.odoo.id
  posix_user {
    uid = var.odoo_uid
    gid = var.odoo_gid
  }
  root_directory {
    path = "/odoo"
    creation_info {
      owner_uid   = var.odoo_uid
      owner_gid   = var.odoo_gid
      permissions = "0750"
    }
  }
  tags = { Name = "${local.name}-odoo-ap", Application = "erp" }
}
