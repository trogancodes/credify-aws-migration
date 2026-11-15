locals {
  ecs_trust = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ecs-tasks.amazonaws.com" } }] })
}
resource "aws_iam_role" "execution" {
  name               = "${local.name}-execution"
  assume_role_policy = local.ecs_trust
}
resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy" "execution_secrets" {
  name = "application-secret-injection"
  role = aws_iam_role.execution.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect   = "Allow", Action = ["secretsmanager:GetSecretValue"],
    Resource = [for k in ["api-db", "lms-db", "erp-db", "odoo-admin"] : aws_secretsmanager_secret.credential[k].arn]
  }] })
}
resource "aws_iam_role" "task" {
  for_each           = local.service_sizes
  name               = "${local.name}-task-${each.key}"
  assume_role_policy = local.ecs_trust
}
resource "aws_iam_role_policy" "efs" {
  name = "odoo-filestore"
  role = aws_iam_role.task["erp"].id
  policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect    = "Allow", Action = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"],
    Resource  = aws_efs_file_system.odoo.arn,
    Condition = { StringEquals = { "elasticfilesystem:AccessPointArn" = aws_efs_access_point.odoo.arn } }
  }] })
}
resource "aws_efs_file_system_policy" "odoo" {
  file_system_id = aws_efs_file_system.odoo.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Deny", Principal = "*", Action = "elasticfilesystem:*", Resource = aws_efs_file_system.odoo.arn,
    Condition = { Bool = { "aws:SecureTransport" = "false" } } },
    { Effect = "Allow", Principal = { AWS = aws_iam_role.task["erp"].arn },
      Action = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"], Resource = aws_efs_file_system.odoo.arn,
    Condition = { StringEquals = { "elasticfilesystem:AccessPointArn" = aws_efs_access_point.odoo.arn } } }
  ] })
}
resource "aws_iam_role" "management" {
  name = "${local.name}-management"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{
    Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" }
  }] })
}
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.management.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
resource "aws_iam_role_policy" "management" {
  name = "lab-operations"
  role = aws_iam_role.management.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Effect = "Allow", Action = ["s3:GetObject"], Resource = "${aws_s3_bucket.lab.arn}/bootstrap/*" },
    { Effect = "Allow", Action = ["s3:PutObject"], Resource = "${aws_s3_bucket.lab.arn}/evidence/*" },
    { Effect = "Allow", Action = ["s3:ListBucket"], Resource = aws_s3_bucket.lab.arn,
    Condition = { StringLike = { "s3:prefix" = ["bootstrap/*", "evidence/*"] } } },
    { Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = [for s in aws_secretsmanager_secret.credential : s.arn] },
    { Effect = "Allow", Action = ["ec2:DescribeNetworkInterfaces", "elasticloadbalancing:DescribeLoadBalancers"], Resource = "*" }
  ] })
}
resource "aws_iam_instance_profile" "management" {
  name = "${local.name}-management"
  role = aws_iam_role.management.name
}
resource "aws_instance" "management" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.lab["mgmt_a"].id
  associate_public_ip_address = false
  vpc_security_group_ids      = [aws_security_group.lab["management"].id]
  iam_instance_profile        = aws_iam_instance_profile.management.name
  user_data                   = file("${path.module}/../scripts/management-user-data.sh")
  user_data_replace_on_change = true
  metadata_options {
    http_tokens = "required"
  }
  root_block_device {
    volume_type           = "gp3"
    volume_size           = 16
    encrypted             = true
    delete_on_termination = true
    tags                  = local.tags
  }
  tags       = { Name = "${local.name}-management" }
  depends_on = [aws_route.private_egress, aws_route.public_internet, aws_route_table_association.lab, aws_iam_role_policy_attachment.ssm]
  lifecycle { ignore_changes = [ami] }
}
