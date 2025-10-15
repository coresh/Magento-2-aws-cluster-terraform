

/////////////////////////////////////////////////////[ CLOUDFRONT MODULE ]////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Generate random uuid string that is intended to be used as secret header
# # ---------------------------------------------------------------------------------------------------------------------#
resource "random_uuid" "secret_header" {}

# # ---------------------------------------------------------------------------------------------------------------------#
# Create a custom CloudFront Response Headers Policy
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_cloudfront_response_headers_policy" "media" {
  name = "${local.project}-response-headers-media"
  cors_config {
    access_control_allow_credentials = false
    access_control_allow_headers { items = ["*"] }
    access_control_allow_methods { items = ["GET"] }
    access_control_allow_origins { items = ["*"] }
    access_control_max_age_sec  = 600
    origin_override             = false
  }

  custom_headers_config {
    items {
      header   = "x-aws-image-optimization"
      value    = "v1.0"
      override = true
    }

    items {
      header   = "vary"
      value    = "accept"
      override = true
    }
  }
}

# # ---------------------------------------------------------------------------------------------------------------------#
# Create Cloudfront distribution with vpc origin and lambda
# # ---------------------------------------------------------------------------------------------------------------------#
module "cloudfront" {
  source              = "terraform-aws-modules/cloudfront/aws"
  version             = "5.0.0"
  aliases             = concat(compact(local.env.aliases))
  comment             = "${local.env.domain} media and static files"
  enabled             = true
  staging             = local.env.cloudfront.staging
  http_version        = local.env.cloudfront.http_version
  is_ipv6_enabled     = local.env.cloudfront.is_ipv6_enabled
  price_class         = local.env.cloudfront.price_class
  retain_on_delete    = local.env.cloudfront.retain_on_delete
  wait_for_deployment = local.env.cloudfront.wait_for_deployment
  continuous_deployment_policy_id = null
  create_monitoring_subscription  = local.env.cloudfront.create_monitoring_subscription
  create_origin_access_identity   = true
  origin_access_identities = {
    s3_bucket_media_optimized = "CloudFront origin access identity"
  }
  create_origin_access_control = true
  origin_access_control = {
    lambda_media_optimization = {
      description      = "Cloudfront origin access control for ${local.project} lambda function"
      origin_type      = "lambda"
      signing_behavior = "always"
      signing_protocol = "sigv4"
    }
  }
  create_vpc_origin = true
  vpc_origin = {
    alb_vpc_origin = {
      name                   = "${local.project}-alb-vpc-origin"
      arn                    = module.alb.arn
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols = {
        items    = ["TLSv1.2"]
        quantity = 1
      }
    }
  }

  origin = {
    s3_bucket_media_optimized = {
      domain_name = module.s3["media-optimized"].s3_bucket_bucket_regional_domain_name
      origin_id   = "${local.env.domain}-media-optimized"
      s3_origin_config = {
        origin_access_identity = "s3_bucket_media_optimized"
      }
    }
    lambda_media_optimization = {
      domain_name           = split("/",module.media_optimization_lambda_package.lambda_function_url)[2]
      origin_id             = "${local.env.domain}-lambda-media-optimization"
      origin_access_control = "lambda_media_optimization"
      custom_origin_config = {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
    }
    origin_shield = {
        enabled               = local.env.cloudfront.origin_shield_enabled
        origin_shield_region  = data.aws_region.current.region
      }
    }
    alb_vpc_origin = {
      domain_name = module.alb.dns_name
      origin_id   = "${local.project}-alb-vpc-origin"
      vpc_origin_config = {
        vpc_origin_id            = "alb_vpc_origin"
        origin_keepalive_timeout = 300
        origin_read_timeout      = 300
      }
      custom_header = [
        {
        name  = "X-${title(local.env.brand)}-Header"
        value = random_uuid.secret_header.result
        }
      ]
    }
  }
  origin_group = {
    media_optimization_group = {
      failover_status_codes      = local.env.cloudfront.failover_criteria_status_codes
      primary_member_origin_id   = "${local.env.domain}-media-optimized"
      secondary_member_origin_id = "${local.env.domain}-lambda-media-optimization"
      origin_id                  = "${local.env.domain}-media-optimization-group"
    }
  }

  ordered_cache_behavior = [ 
   {
    path_pattern     = local.env.cloudfront.path_pattern
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.env.domain}-media-optimization-group"	
    origin_request_policy_id   = "216adef6-5c7f-47e4-b989-5492eafa07d3"
    response_headers_policy_id = aws_cloudfront_response_headers_policy.media.id
    cache_policy_id            = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    viewer_protocol_policy     = "https-only"
    compress                   = false
	use_forwarded_values       = false
   },
   {
    path_pattern     = "admin_*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.project}-alb-vpc-origin"	
    origin_request_policy_id   = "216adef6-5c7f-47e4-b989-5492eafa07d3"
    cache_policy_id            = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    viewer_protocol_policy     = "https-only"
    compress                   = true
	use_forwarded_values       = false
   }
   ]
   
   default_cache_behavior = {
     allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
     cached_methods   = ["GET", "HEAD"]
     target_origin_id = "${local.project}-alb-vpc-origin"
     origin_request_policy_id = "216adef6-5c7f-47e4-b989-5492eafa07d3"
     cache_policy_id          = "658327ea-f89d-4fab-a63d-7e88639e58f6"
     viewer_protocol_policy   = "https-only"
     compress                 = true
	 use_forwarded_values     = false
  }

  logging_config = {
    bucket = module.s3["logs"].s3_bucket_bucket_domain_name
    prefix = "cloudfront"
  }
    geo_restriction = {
      restriction_type = "blacklist"
      locations        = local.env.waf.restricted_countries
  }
  viewer_certificate = {
    acm_certificate_arn      = try(module.acm_cloudfront.acm_certificate_arn, module.acm.acm_certificate_arn, null)
    ssl_support_method       = "sni-only"
    minimum_protocol_version = local.env.cloudfront.minimum_protocol_version
  }
}
