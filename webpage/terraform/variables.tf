variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "bucket_name" {
  description = "S3 bucket name for the static website"
  type        = string
  default     = "eyed-website"
}

variable "domain_name" {
  description = "Custom domain name (e.g. eyed.example.com). Leave empty to use CloudFront default domain."
  type        = string
  default     = ""
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for HTTPS on custom domain. Required if domain_name is set. Must be in us-east-1."
  type        = string
  default     = ""
}

variable "cloudfront_price_class" {
  description = "CloudFront price class"
  type        = string
  default     = "PriceClass_100"
}
