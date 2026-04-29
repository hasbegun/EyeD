# EyeD Website

Static marketing page for the EyeD project, hosted on AWS S3 + CloudFront.

## Local Preview

```bash
# Open directly in browser
open index.html

# Or use a local server
python3 -m http.server 8000 --directory .
# → http://localhost:8000
```

## Deploy to AWS

### Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- AWS CLI configured (`aws configure`)

### Quick Deploy

```bash
cd terraform

# Initialize
terraform init

# Preview changes
terraform plan -var="bucket_name=eyed-website"

# Deploy
terraform apply -var="bucket_name=eyed-website"
```

### Custom Domain

```bash
terraform apply \
  -var="bucket_name=eyed-website" \
  -var="domain_name=eyed.example.com" \
  -var="acm_certificate_arn=arn:aws:acm:us-east-1:123456789:certificate/abc-123"
```

> **Note:** ACM certificate must be in `us-east-1` for CloudFront.

### Update Content

After editing `index.html`:

```bash
cd terraform
terraform apply -var="bucket_name=eyed-website"

# Invalidate CloudFront cache for immediate update
aws cloudfront create-invalidation \
  --distribution-id $(terraform output -raw cloudfront_distribution_id) \
  --paths "/*"
```

### Tear Down

```bash
cd terraform
terraform destroy -var="bucket_name=eyed-website"
```

## Structure

```
webpage/
├── index.html          # Static site (single file, no dependencies)
├── README.md
└── terraform/
    ├── main.tf         # S3 bucket, CloudFront, OAC, bucket policy
    ├── variables.tf    # Configurable inputs
    ├── outputs.tf      # URLs and IDs
    └── .gitignore      # Exclude .terraform/ and state files
```
