provider "aws" {
  region = var.aws_region
  shared_credentials_file = "~/.aws/credentials"
  version                 = "~> 2.0"
}

#-----S3-----

#create the static website bucket in S3

resource "aws_s3_bucket" "main" {
  bucket = var.domain_name
  acl    = "public-read"

  website {
    index_document = "index.html"
  }
}

resource "aws_s3_bucket" "alt" {
  bucket = "www.${var.domain_name}"
  acl    = "public-read"

  website {
    redirect_all_requests_to = "https://davidhulsman.me.uk"
  }
}
#-----CloudFront-----

#origin access identity

resource "aws_cloudfront_origin_access_identity" "resumeOA" {
  comment = "origin access for my resume distribution"
}

#cloudfront distribution

resource "aws_cloudfront_distribution" "s3_distribution" {
  depends_on = [aws_cloudfront_origin_access_identity.resumeOA]

  origin {
    domain_name = aws_s3_bucket.resume_code.bucket_regional_domain_name
    origin_id   = aws_cloudfront_origin_access_identity.resumeOA.id

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.resumeOA.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases = [
    var.domain_name,
  "www.${var.domain_name}"]

  default_cache_behavior {
    allowed_methods = [
      "DELETE",
      "GET",
      "HEAD",
      "OPTIONS",
      "PATCH",
      "POST",
    "PUT"]
    cached_methods = [
      "GET",
    "HEAD"]
    target_origin_id = aws_cloudfront_origin_access_identity.resumeOA.id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cert.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2019"
  }
}

#-----ACM Certificate-----

#create new acm

resource "aws_acm_certificate" "cert" {
  domain_name               = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  name    = aws_acm_certificate.cert.domain_validation_options.0.resource_record_name
  type    = aws_acm_certificate.cert.domain_validation_options.0.resource_record_type
  zone_id = data.aws_route53_zone.primary.zone_id
  records = [aws_acm_certificate.cert.domain_validation_options.0.resource_record_value]
  ttl     = 60
}

resource "aws_route53_record" "cert_validation_alt1" {
  name    = aws_acm_certificate.cert.domain_validation_options.1.resource_record_name
  type    = aws_acm_certificate.cert.domain_validation_options.1.resource_record_type
  zone_id = data.aws_route53_zone.primary.zone_id
  records = [aws_acm_certificate.cert.domain_validation_options.1.resource_record_value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn = aws_acm_certificate.cert.arn
  validation_record_fqdns = [
    aws_route53_record.cert_validation.fqdn,
    aws_route53_record.cert_validation_alt1.fqdn
  ]
}

#-----Route53-----

#import zone already made for blog

data "aws_route53_zone" "primary" {
  name = var.domain_name
}

#www

resource "aws_route53_record" "www" {
  name    = "www.${var.domain_name}"
  type    = "A"
  zone_id = data.aws_route53_zone.primary.zone_id

  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
  }
}

#-----DynamoDB-----

#table

resource "aws_dynamodb_table" "VisitorTable" {
  hash_key     = "Site"
  name         = "VisitorTable"
  billing_mode = "PAY_PER_REQUEST"
  attribute {
    name = "Site"
    type = "S"
  }
}

#add first item but only the first time run

resource "aws_dynamodb_table_item" "VisitorTableItem" {
  table_name = aws_dynamodb_table.VisitorTable.name
  hash_key   = aws_dynamodb_table.VisitorTable.hash_key
  lifecycle { ignore_changes = [item] }

  item = <<ITEM
{
  "Site": {"S": "Resume"},
  "Visitors": {"N": "0"}
}
ITEM
}