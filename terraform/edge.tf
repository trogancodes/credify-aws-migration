resource "aws_lb" "lab" {
  name               = "${local.name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lab["alb"].id]
  subnets            = [aws_subnet.lab["public_a"].id, aws_subnet.lab["public_b"].id]
  idle_timeout       = 300
  tags               = { Name = "${local.name}-alb" }
}
resource "aws_lb_target_group" "app" {
  for_each             = { api = 3000, erp = 8069 }
  name                 = "${local.name}-${each.key}-tg"
  port                 = each.value
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = aws_vpc.lab.id
  deregistration_delay = 30
  health_check {
    path                = each.key == "api" ? "/health" : "/web/login"
    matcher             = each.key == "api" ? "200" : "200-399"
    interval            = 30
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 5
  }
}
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.lab.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app["erp"].arn
  }
}
resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app["api"].arn
  }
  condition {
    path_pattern { values = ["/api/*", "/health"] }
  }
}
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${local.name}-frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}
data "aws_cloudfront_cache_policy" "disabled" { name = "Managed-CachingDisabled" }
data "aws_cloudfront_origin_request_policy" "all" { name = "Managed-AllViewer" }
resource "aws_cloudfront_distribution" "lab" {
  enabled             = true
  comment             = "Credify student 5 lab; manual 8.3 HTTPS exception"
  default_root_object = "index.html"
  price_class         = "PriceClass_All"
  web_acl_id          = var.enable_waf ? aws_wafv2_web_acl.lab[0].arn : null
  origin {
    domain_name              = aws_s3_bucket.lab.bucket_regional_domain_name
    origin_id                = "frontend"
    origin_path              = "/frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }
  origin {
    domain_name = aws_lb.lab.dns_name
    origin_id   = "applications"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
  default_cache_behavior {
    target_origin_id       = "frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.disabled.id
    compress               = true
  }
  dynamic "ordered_cache_behavior" {
    for_each = ["/api/*", "/health", "/web*", "/report/*", "/mail/*"]
    content {
      path_pattern             = ordered_cache_behavior.value
      target_origin_id         = "applications"
      viewer_protocol_policy   = "redirect-to-https"
      allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods           = ["GET", "HEAD"]
      cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
      origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all.id
      compress                 = true
    }
  }
  restrictions {
    geo_restriction { restriction_type = "none" }
  }
  viewer_certificate { cloudfront_default_certificate = true }
  tags = { Name = "${local.name}-edge", Application = "frontend" }
}
resource "aws_wafv2_web_acl" "lab" {
  count    = var.enable_waf ? 1 : 0
  provider = aws.edge
  name     = "${local.name}-waf"
  scope    = "CLOUDFRONT"
  default_action {
    allow {}
  }
  rule {
    name     = "common-rules"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name}-common"
      sampled_requests_enabled   = true
    }
  }
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name}-waf"
    sampled_requests_enabled   = true
  }
}
