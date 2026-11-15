output "phase" { value = var.phase }
output "region" { value = var.region }
output "bucket_name" { value = aws_s3_bucket.lab.id }
output "vpc_id" { value = aws_vpc.lab.id }
output "subnets" { value = { for k, s in aws_subnet.lab : k => { id = s.id, cidr = s.cidr_block, az = s.availability_zone } } }
output "management_instance_id" { value = aws_instance.management.id }
output "ecr_repositories" { value = { for k, r in aws_ecr_repository.app : k => r.repository_url } }
output "cloudfront_url" { value = "https://${aws_cloudfront_distribution.lab.domain_name}" }
output "odoo_setup_url" { value = "https://${aws_cloudfront_distribution.lab.domain_name}/web/database/manager" }
output "odoo_login_url" { value = "https://${aws_cloudfront_distribution.lab.domain_name}/web/login" }
output "alb_dns" { value = aws_lb.lab.dns_name }
output "database_endpoints" { value = { for k, db in aws_db_instance.primary : k => db.address } }
output "core_replica_endpoint" { value = local.replica ? aws_db_instance.core_read[0].address : null }
output "odoo_master_secret_arn" { value = aws_secretsmanager_secret.credential["odoo-admin"].arn }
output "download_payload_commands" {
  value = <<-EOT
    export AWS_DEFAULT_REGION=${var.region}
    unset AWS_PROFILE
    mkdir -p ~/credify-work
    cd ~/credify-work
    aws s3 cp s3://${aws_s3_bucket.lab.id}/bootstrap/lab-payload.zip .
    unzip -o lab-payload.zip
    aws s3 cp s3://${aws_s3_bucket.lab.id}/bootstrap/lab-config.json .
  EOT
}
output "image_tag" { value = var.image_tag }
