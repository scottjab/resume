provider "aws" {
  //region = "us-west-2"

  region = "us-east-1"
}

provider "aws" {
  region = "us-west-2"
  alias  = "us-west-2"
}

variable "www_domain_name" {
  default = "www.scottjab.codes"
}

variable "root_domain_name" {
  default = "scottjab.codes"
}

resource "aws_s3_bucket" "www" {
  bucket   = "${var.www_domain_name}"
  acl      = "public-read"
  provider = "aws.us-west-2"

  policy = <<POLICY
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Sid":"AddPerm",
      "Effect":"Allow",
      "Principal": "*",
      "Action":["s3:GetObject"],
      "Resource":["arn:aws:s3:::${var.www_domain_name}/*"]
    }
  ]
}
POLICY

  website {
    index_document = "index.html"
    error_document = "index.html"
  }
}

resource "aws_s3_bucket_object" "index_html" {
  bucket     = "${var.www_domain_name}"
  key        = "index.html"
  source     = "index.html"
  etag       = "${md5(file("index.html"))}"
  depends_on = ["aws_s3_bucket.www"]
  provider   = "aws.us-west-2"
}

resource "aws_s3_bucket_object" "index_pdf" {
  bucket     = "${var.www_domain_name}"
  key        = "resume.pdf"
  source     = "resume.pdf"
  etag       = "${md5(file("resume.pdf"))}"
  depends_on = ["aws_s3_bucket.www"]
  provider   = "aws.us-west-2"
}

resource "aws_acm_certificate" "cert" {
  domain_name               = "${var.root_domain_name}"
  validation_method         = "DNS"
  subject_alternative_names = ["${var.www_domain_name}"]

  // provider                  = "aws.us-east-1"
}

// validate 
resource "aws_route53_record" "cert_validation" {
  name    = "${aws_acm_certificate.cert.domain_validation_options.0.resource_record_name}"
  type    = "${aws_acm_certificate.cert.domain_validation_options.0.resource_record_type}"
  zone_id = "${aws_route53_zone.zone.id}"
  records = ["${aws_acm_certificate.cert.domain_validation_options.0.resource_record_value}"]
  ttl     = 60

  //  provider                  = "aws.us-east-1"
}

resource "aws_route53_record" "cert_validation_alt1" {
  name    = "${aws_acm_certificate.cert.domain_validation_options.1.resource_record_name}"
  type    = "${aws_acm_certificate.cert.domain_validation_options.1.resource_record_type}"
  zone_id = "${aws_route53_zone.zone.id}"
  records = ["${aws_acm_certificate.cert.domain_validation_options.1.resource_record_value}"]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn = "${aws_acm_certificate.cert.arn}"

  validation_record_fqdns = ["${aws_route53_record.cert_validation.fqdn}",
    "${aws_route53_record.cert_validation_alt1.fqdn}",
  ]
}

resource "aws_cloudfront_distribution" "www_distribution" {
  origin {
    custom_origin_config {
      http_port              = "80"
      https_port             = "443"
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }

    domain_name = "${aws_s3_bucket.www.website_endpoint}"
    origin_id   = "${var.www_domain_name}"
  }

  enabled = true

  default_root_object = "index.html"

  default_cache_behavior {
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "${var.www_domain_name}"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 31536000

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  aliases = ["${var.www_domain_name}"]

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  // Here's where our certificate is loaded in!
  viewer_certificate {
    acm_certificate_arn = "${aws_acm_certificate_validation.cert.certificate_arn}"
    ssl_support_method  = "sni-only"
  }

  depends_on = ["aws_acm_certificate.cert", "aws_s3_bucket_object.index_html", "aws_s3_bucket_object.index_pdf"]
}

resource "aws_route53_zone" "zone" {
  name = "${var.root_domain_name}"
}

resource "aws_route53_record" "www" {
  zone_id = "${aws_route53_zone.zone.zone_id}"
  name    = "${var.www_domain_name}"
  type    = "A"

  alias {
    name                   = "${aws_cloudfront_distribution.www_distribution.domain_name}"
    zone_id                = "${aws_cloudfront_distribution.www_distribution.hosted_zone_id}"
    evaluate_target_health = false
  }
}

# root
resource "aws_s3_bucket" "root" {
  bucket   = "${var.root_domain_name}"
  acl      = "public-read"
  provider = "aws.us-west-2"

  policy = <<POLICY
{
  "Version":"2012-10-17",
  "Statement":[
    {
      "Sid":"AddPerm",
      "Effect":"Allow",
      "Principal": "*",
      "Action":["s3:GetObject"],
      "Resource":["arn:aws:s3:::${var.root_domain_name}/*"]
    }
  ]
}
POLICY

  website {
    // Note this redirect. Here's where the magic happens.
    redirect_all_requests_to = "https://${var.www_domain_name}"
  }
}

resource "aws_cloudfront_distribution" "root_distribution" {
  origin {
    custom_origin_config {
      http_port              = "80"
      https_port             = "443"
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }

    domain_name = "${aws_s3_bucket.root.website_endpoint}"
    origin_id   = "${var.root_domain_name}"
  }

  enabled             = true
  default_root_object = "index.html"

  default_cache_behavior {
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "${var.root_domain_name}"
    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  aliases = ["${var.root_domain_name}"]

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = "${aws_acm_certificate_validation.cert.certificate_arn}"
    ssl_support_method  = "sni-only"
  }

  depends_on = ["aws_acm_certificate.cert"]
}

resource "aws_route53_record" "root" {
  zone_id = "${aws_route53_zone.zone.zone_id}"

  // NOTE: name is blank here.
  name = ""
  type = "A"

  alias = {
    name                   = "${aws_cloudfront_distribution.root_distribution.domain_name}"
    zone_id                = "${aws_cloudfront_distribution.root_distribution.hosted_zone_id}"
    evaluate_target_health = false
  }
}
