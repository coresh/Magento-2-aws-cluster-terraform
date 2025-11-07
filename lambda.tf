

///////////////////////////////////////////////////////[ LAMBDA MODULE ]//////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create Lambda function for imgproxy
# # ---------------------------------------------------------------------------------------------------------------------#

module "imgproxy" {  
  source         = "terraform-aws-modules/lambda/aws"
  version        = "8.1.2"
  create         = true
  function_name  = "${local.project}-imgproxy"
  description    = "Imgproxy image processing service for ${local.env.domain}"
  package_type   = "Image"
  create_package = false
  image_uri      = "${module.ecr["imgproxy"].repository_url}:${local.env.imgproxy.image}"
  memory_size    = local.env.lambda.memory_size
  timeout        = local.env.lambda.timeout
  architectures  = ["arm64"]
  environment_variables = {
    PORT                                = local.env.imgproxy.port
    IMGPROXY_USE_S3                     = local.env.imgproxy.use_s3
    IMGPROXY_ALLOW_INSECURE             = local.env.imgproxy.allow_insecure
    IMGPROXY_ALLOWED_PROCESSING_OPTIONS = local.env.imgproxy.allowed_processing_options
    IMGPROXY_ALLOW_ORIGIN               = local.env.imgproxy.allow_origin
    IMGPROXY_ALLOWED_SOURCES            = local.env.imgproxy.allowed_sources
    IMGPROXY_FALLBACK_IMAGE_PATH        = local.env.imgproxy.fallback_image_path
    IMGPROXY_WATERMARK_PATH             = local.env.imgproxy.watermark_path
    IMGPROXY_MAX_REDIRECTS              = local.env.imgproxy.max_redirects
    IMGPROXY_TTL                        = local.env.imgproxy.ttl
    IMGPROXY_AUTO_WEBP                  = local.env.imgproxy.auto_webp
    IMGPROXY_AUTO_AVIF                  = local.env.imgproxy.auto_avif
    IMGPROXY_QUALITY                    = local.env.imgproxy.quality
    IMGPROXY_FORMAT_QUALITY             = local.env.imgproxy.format_quality
    IMGPROXY_USE_ETAG                   = local.env.imgproxy.use_etag
    IMGPROXY_ENABLE_DEBUG_HEADERS       = local.env.imgproxy.enable_debug_headers
    IMGPROXY_LOG_FORMAT                 = local.env.imgproxy.log_format
    IMGPROXY_LOG_LEVEL                  = local.env.imgproxy.log_level
    IMGPROXY_CLOUD_WATCH_SERVICE_NAME   = local.env.imgproxy.cloud_watch_service_name
    IMGPROXY_CLOUD_WATCH_NAMESPACE      = local.env.imgproxy.cloud_watch_namespace
    IMGPROXY_CLOUD_WATCH_REGION         = data.aws_region.current.region
  }
  create_lambda_function_url        = true
  authorization_type                = "AWS_IAM"
  invoke_mode                       = local.env.lambda.invoke_mode
  tracing_mode                      = local.env.lambda.tracing_mode
  cloudwatch_logs_retention_in_days = local.env.lambda.cloudwatch_logs_retention_in_days
  logging_log_format                = local.env.lambda.logging_log_format
  attach_policy_json = true
  policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "cloudwatch:PutMetricStream"
        ]
        Resource = "*"
      }
    ]
  })
}
