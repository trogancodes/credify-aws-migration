terraform {
  required_version = ">= 1.11.0, < 2.0.0"
  required_providers {
    aws     = { source = "hashicorp/aws", version = "= 6.20.0" }
    random  = { source = "hashicorp/random", version = "= 3.7.2" }
    archive = { source = "hashicorp/archive", version = "= 2.7.1" }
  }
}
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.aws_account_id]
  default_tags { tags = local.tags }
}
# WAF for CloudFront is administered in us-east-1; this does NOT create a DR VPC.
provider "aws" {
  alias               = "edge"
  region              = "us-east-1"
  allowed_account_ids = [var.aws_account_id]
  default_tags { tags = local.tags }
}
