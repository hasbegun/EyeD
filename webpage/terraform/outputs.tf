output "s3_bucket_name" {
  description = "Name of the S3 bucket"
  value       = aws_s3_bucket.website.id
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (for cache invalidation)"
  value       = aws_cloudfront_distribution.website.id
}

output "cloudfront_domain" {
  description = "CloudFront domain name"
  value       = aws_cloudfront_distribution.website.domain_name
}

output "website_url" {
  description = "Website URL"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "https://${aws_cloudfront_distribution.website.domain_name}"
}
