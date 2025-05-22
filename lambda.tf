

/////////////////////////////////////////////////////[ LAMBDA@EDGE MODULE ]///////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create Lambda@Edge package and publish
# # ---------------------------------------------------------------------------------------------------------------------#
module "media_optimization_lambda_package" {
  source         = "terraform-aws-modules/lambda/aws"
  version        = "7.20.2"
  providers      = { aws = aws.us-east-1 }
  function_name  = "${local.project}-media-optimization"
  description    = "Lambda@Edge function to optimize media before cloudfront"
  handler        = "index.handler"
  runtime        = "nodejs20.x"
  lambda_at_edge = true
  publish        = true
  create_package = true
  source_path = {
    path             = "${abspath(path.root)}/lambda"
    npm_requirements = true
  }
  hash_extra     = filebase64sha256("${abspath(path.root)}/lambda/index.mjs")
  store_on_s3    = false
  s3_bucket      = module.s3["lambda"].s3_bucket_id
  s3_prefix      = "lambda-edge-media-optimization/"
  create_lambda_function_url = true
  authorization_type         = "AWS_IAM"
  environment_variables  = {
      s3BucketRegion             = module.s3["media"].s3_bucket_region
      originalImageBucketName    = module.s3["media"].s3_bucket_id
      transformedImageBucketName = module.s3["media-optimized"].s3_bucket_id
      transformedImageCacheTTL   = "max-age=31622400"
      maxImageSize               = "4700000"
  }
  allowed_triggers = {
    Cloudfront = {
      principal  = "cloudfront.amazonaws.com"
      source_arn = module.cloudfront.cloudfront_distribution_arn
    }
  }
}
