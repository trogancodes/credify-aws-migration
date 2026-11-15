resource "aws_cloudwatch_metric_alarm" "cpu" {
  alarm_name          = "${local.name}-core-cpu"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.primary["core"].identifier }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
}
resource "aws_cloudwatch_metric_alarm" "storage" {
  alarm_name          = "${local.name}-core-storage"
  namespace           = "AWS/RDS"
  metric_name         = "FreeStorageSpace"
  dimensions          = { DBInstanceIdentifier = aws_db_instance.primary["core"].identifier }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 5368709120
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "missing"
}
resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${local.name}-api-5xx"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = aws_lb.lab.arn_suffix, TargetGroup = aws_lb_target_group.app["api"].arn_suffix }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
}
resource "aws_cloudwatch_dashboard" "lab" {
  dashboard_name = local.name
  dashboard_body = jsonencode({ widgets = [
    { type = "metric", x = 0, y = 0, width = 12, height = 6, properties = {
      title   = "RDS CPU", region = var.region, stat = "Average", period = 60,
      metrics = concat([for db in aws_db_instance.primary : ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", db.identifier]], local.replica ? [["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", aws_db_instance.core_read[0].identifier]] : [])
    } },
    { type = "metric", x = 12, y = 0, width = 12, height = 6, properties = {
      title   = "RDS free storage", region = var.region, stat = "Minimum", period = 60,
      metrics = [for db in aws_db_instance.primary : ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", db.identifier]]
    } },
    { type = "metric", x = 0, y = 6, width = 12, height = 6, properties = {
      title   = "Three services CPU", region = var.region, stat = "Average", period = 60,
      metrics = [for name in keys(local.service_sizes) : ["AWS/ECS", "CPUUtilization", "ClusterName", local.name, "ServiceName", "${local.name}-${name}"]]
    } },
    { type = "metric", x = 12, y = 6, width = 12, height = 6, properties = {
      title   = "Three services memory", region = var.region, stat = "Average", period = 60,
      metrics = [for name in keys(local.service_sizes) : ["AWS/ECS", "MemoryUtilization", "ClusterName", local.name, "ServiceName", "${local.name}-${name}"]]
    } },
    { type = "metric", x = 0, y = 12, width = 12, height = 6, properties = {
      title   = "Healthy ALB targets", region = var.region, stat = "Minimum", period = 60,
      metrics = [for tg in aws_lb_target_group.app : ["AWS/ApplicationELB", "HealthyHostCount", "LoadBalancer", aws_lb.lab.arn_suffix, "TargetGroup", tg.arn_suffix]]
    } },
    { type = "metric", x = 12, y = 12, width = 12, height = 6, properties = {
      title   = "API target errors", region = var.region, stat = "Sum", period = 60,
      metrics = [["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", aws_lb.lab.arn_suffix, "TargetGroup", aws_lb_target_group.app["api"].arn_suffix]]
    } },
    { type = "alarm", x = 0, y = 18, width = 12, height = 4, properties = {
      title = "Required alarms", alarms = [aws_cloudwatch_metric_alarm.cpu.arn, aws_cloudwatch_metric_alarm.storage.arn, aws_cloudwatch_metric_alarm.api_5xx.arn]
    } },
    { type = "metric", x = 12, y = 18, width = 12, height = 4, properties = {
      title   = "Core replica lag (appears after replica phase)", region = var.region, stat = "Maximum", period = 60,
      metrics = [["AWS/RDS", "ReplicaLag", "DBInstanceIdentifier", "${local.name}-core-ro"]]
    } }
  ] })
}
# One management-events trail in the lab Region; no costly S3 data-event selectors.
resource "aws_s3_bucket_policy" "lab" {
  bucket = aws_s3_bucket.lab.id
  policy = jsonencode({ Version = "2012-10-17", Statement = [
    { Sid      = "HTTPSOnly", Effect = "Deny", Principal = "*", Action = "s3:*",
      Resource = [aws_s3_bucket.lab.arn, "${aws_s3_bucket.lab.arn}/*"],
    Condition = { Bool = { "aws:SecureTransport" = "false" } } },
    { Sid = "CloudFrontFrontendOnly", Effect = "Allow", Principal = { Service = "cloudfront.amazonaws.com" }, Action = "s3:GetObject",
    Resource = "${aws_s3_bucket.lab.arn}/frontend/*", Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.lab.arn } } },
    { Sid = "TrailACL", Effect = "Allow", Principal = { Service = "cloudtrail.amazonaws.com" }, Action = "s3:GetBucketAcl", Resource = aws_s3_bucket.lab.arn,
    Condition = { StringEquals = { "aws:SourceArn" = "arn:aws:cloudtrail:${var.region}:${var.aws_account_id}:trail/${local.name}" } } },
    { Sid      = "TrailWrite", Effect = "Allow", Principal = { Service = "cloudtrail.amazonaws.com" }, Action = "s3:PutObject",
      Resource = "${aws_s3_bucket.lab.arn}/audit/AWSLogs/${var.aws_account_id}/*",
    Condition = { StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control", "aws:SourceArn" = "arn:aws:cloudtrail:${var.region}:${var.aws_account_id}:trail/${local.name}" } } }
  ] })
}
resource "aws_cloudtrail" "lab" {
  name                          = local.name
  s3_bucket_name                = aws_s3_bucket.lab.id
  s3_key_prefix                 = "audit"
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true
  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }
  depends_on = [aws_s3_bucket_policy.lab]
}
