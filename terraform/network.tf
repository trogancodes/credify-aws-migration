resource "aws_vpc" "lab" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${local.name}-vpc" }
  depends_on           = [terraform_data.guardrails]
}
locals {
  subnets = {
    public_a = { cidr = "10.105.0.0/24", az = 0, tier = "public" }
    public_b = { cidr = "10.105.1.0/24", az = 1, tier = "public" }
    app_a    = { cidr = "10.105.10.0/24", az = 0, tier = "app" }
    app_b    = { cidr = "10.105.11.0/24", az = 1, tier = "app" }
    data_a   = { cidr = "10.105.20.0/24", az = 0, tier = "data" }
    data_b   = { cidr = "10.105.21.0/24", az = 1, tier = "data" }
    mgmt_a   = { cidr = "10.105.30.0/24", az = 0, tier = "management" }
  }
}
resource "aws_subnet" "lab" {
  for_each                = local.subnets
  vpc_id                  = aws_vpc.lab.id
  cidr_block              = each.value.cidr
  availability_zone       = data.aws_availability_zones.available.names[each.value.az]
  map_public_ip_on_launch = false
  tags                    = { Name = "${local.name}-${replace(each.key, "_", "-")}" }
}
resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id
  tags   = { Name = "${local.name}-igw" }
}
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${local.name}-nat-eip" }
}
resource "aws_nat_gateway" "single" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.lab["public_a"].id
  tags          = { Name = "${local.name}-nat-a" }
  depends_on    = [aws_internet_gateway.lab]
}
resource "aws_route_table" "tier" {
  for_each = toset(["public", "app", "data", "management"])
  vpc_id   = aws_vpc.lab.id
  tags     = { Name = "${local.name}-rt-${each.key}" }
}
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.tier["public"].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.lab.id
}
resource "aws_route" "private_egress" {
  for_each               = toset(["app", "management"])
  route_table_id         = aws_route_table.tier[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.single.id
}
resource "aws_route_table_association" "lab" {
  for_each       = local.subnets
  subnet_id      = aws_subnet.lab[each.key].id
  route_table_id = aws_route_table.tier[each.value.tier].id
}
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.lab.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.tier["app"].id, aws_route_table.tier["management"].id]
  tags              = { Name = "${local.name}-s3" }
}
