resource "aws_security_group" "lab" {
  for_each    = toset(["alb", "api", "lms", "erp", "core", "erpdb", "maria", "management", "efs"])
  name        = "${local.name}-sg-${each.key}"
  description = "Credify student 5 ${each.key}; no SSH"
  vpc_id      = aws_vpc.lab.id
  tags        = { Name = "${local.name}-sg-${each.key}" }
}
locals {
  connections = {
    test_alb   = { from = "management", to = "alb", port = 80 }
    alb_api    = { from = "alb", to = "api", port = 3000 }
    alb_erp    = { from = "alb", to = "erp", port = 8069 }
    api_lms    = { from = "api", to = "lms", port = 4000 }
    test_lms   = { from = "management", to = "lms", port = 4000 }
    api_core   = { from = "api", to = "core", port = 5432 }
    test_core  = { from = "management", to = "core", port = 5432 }
    erp_db     = { from = "erp", to = "erpdb", port = 5432 }
    test_erpdb = { from = "management", to = "erpdb", port = 5432 }
    lms_maria  = { from = "lms", to = "maria", port = 3306 }
    test_maria = { from = "management", to = "maria", port = 3306 }
    erp_efs    = { from = "erp", to = "efs", port = 2049 }
  }
}
resource "aws_vpc_security_group_ingress_rule" "connection" {
  for_each                     = local.connections
  security_group_id            = aws_security_group.lab[each.value.to].id
  referenced_security_group_id = aws_security_group.lab[each.value.from].id
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  description                  = each.key
}
resource "aws_vpc_security_group_egress_rule" "connection" {
  for_each                     = local.connections
  security_group_id            = aws_security_group.lab[each.value.from].id
  referenced_security_group_id = aws_security_group.lab[each.value.to].id
  ip_protocol                  = "tcp"
  from_port                    = each.value.port
  to_port                      = each.value.port
  description                  = each.key
}
resource "aws_vpc_security_group_egress_rule" "https" {
  for_each          = toset(["api", "lms", "erp", "management"])
  security_group_id = aws_security_group.lab[each.key].id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "AWS APIs and packages through single NAT"
}
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}
resource "aws_vpc_security_group_ingress_rule" "cloudfront" {
  security_group_id = aws_security_group.lab["alb"].id
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  description       = "Manual 8.3 CloudFront HTTP origin exception"
}
