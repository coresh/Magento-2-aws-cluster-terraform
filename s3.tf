

/////////////////////////////////////////////////////[ S3 BUCKETS MODULE ]////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create SSM Parameterstore for s3 env
# # ---------------------------------------------------------------------------------------------------------------------#

locals {
  s3 = merge([
    for s3_key, s3_output in module.s3 : {
      "S3_${upper(s3_key)}_BUCKET_ID"                   = s3_output.s3_bucket_id
      "S3_${upper(s3_key)}_BUCKET_ARN"                  = s3_output.s3_bucket_arn
      "S3_${upper(s3_key)}_BUCKET_DOMAIN_NAME"          = s3_output.s3_bucket_bucket_domain_name
      "S3_${upper(s3_key)}_BUCKET_REGIONAL_DOMAIN_NAME" = s3_output.s3_bucket_bucket_regional_domain_name
    }
  ]...)
}

resource "aws_ssm_parameter" "s3" {
  for_each    = local.s3
  name        = "/${local.project}/${each.key}"
  description = "S3 parameter: ${each.key}"
  type        = "String"
  value       = each.value
  tags = {
    Service   = "s3"
  }
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create S3 bucket policy
# # ---------------------------------------------------------------------------------------------------------------------#
data "aws_iam_policy_document" "logs" {
  statement {
    sid    = "ALBS3Access"
    effect = "Allow"
    actions = [
      "s3:PutObject"
    ]
    resources = ["${module.s3["logs"].arn}/ALB_logs/*"]
    principals {
      type        = "AWS"
      identifiers = [module.alb.arn]
    }
  }
  statement {
    sid    = "CloudFrontS3Access"
    effect = "Allow"
    actions = [
      "s3:PutObject"
    ]
    resources = ["${module.s3["logs"].s3_bucket_arn}/cloudfront/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "AWS:SourceArn"
      values   = [module.cloudfront.cloudfront_distribution_arn]
    }
  }
}

data "aws_iam_policy_document" "releases" {
 statement {
    sid    = "AllowCodebuildS3Access"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning"
    ]
    resources = [
      "${module.s3["releases"].s3_bucket_arn}",
      "${module.s3["releases"].s3_bucket_arn}/*"
    ]
    principals {
      type        = "AWS"
      identifiers =  aws_iam_role.codebuild.arn
    }
  }
}

data "aws_iam_policy_document" "media" {
  statement {
    sid       = "ECSS3Access"
    effect    = "Allow"
    actions = [
      "s3:PutObject",
      "s3:ListBucket"
    ]
    resources = [
      "${moduel.s3["media"].arn}",
      "${moduel.s3["media"].arn}/*"
    ]
    principals {
      type        = "AWS"
      identifiers = [module.ecs_cluster.task_exec_iam_role_arn]
    }
  }
  statement {
    sid       = "LambdaS3Access"
    effect    = "Allow"
    actions = [
      "s3:GetObject"
    ]
    resources = ["${moduel.s3["media"].arn}/*"]
    principals {
      type        = "AWS"
      identifiers = [module.imgproxy.lambda_function_arn]
    }
  }
  statement {
    sid    = "CloudFrontS3Access"
    effect = "Allow"
    actions = [
      "s3:GetObject"
    ]
    resources = ["${module.s3["media"].s3_bucket_arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "AWS:SourceArn"
      values   = [module.cloudfront.cloudfront_distribution_arn]
    }
  }
}

data "aws_iam_policy_document" "backup" {
  statement {
    sid    = "SSMS3Access"
    effect = "Allow"
    actions = [
      "s3:PutObject"
    ]
    resources = ["${module.s3["backup"].arn}/*"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.ssm_service_role.arn]
    }
  }
}

locals {
  bucket_policy = {
    for name in local.env.s3bucket : name => data.aws_iam_policy_document[name].json
  }
}

# # ---------------------------------------------------------------------------------------------------------------------#
# Create S3 buckets
# # ---------------------------------------------------------------------------------------------------------------------#
module "s3" {
  source   = "terraform-aws-modules/s3-bucket/aws"
  version  = "5.8.1"
  for_each = local.env.s3.bucket
  bucket   = "${local.project}-${each.key}"
  acl      = "private"
  attach_policy            = true
  policy                   = local.bucket_policy[each.key]
  force_destroy            = true
  control_object_ownership = true
  object_ownership         = "ObjectWriter"
  expected_bucket_owner    = data.aws_caller_identity.current.account_id
  attach_elb_log_delivery_policy = each.key == "logs" ? true : false
  versioning = {
    enabled = each.value.versioning
  }  
  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm     = "aws:kms"
      }
    }
  }
  intelligent_tiering = {
    general = {
      status = each.value.intelligent_tiering.status
      tiering = {
        ARCHIVE_ACCESS = { days = 90 }
      }
    }
  }
  lifecycle_rule = [
    {
      id      = "delete-unaccessed-after-90-days"
      status  = each.value.lifecycle_rule.status
      filter  = {}
      expiration = {
        days = 91
      }
      abort_incomplete_multipart_upload_days = 7
    }
  ]
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Configure S3 buckets notifications for example to eventbridge
# # ---------------------------------------------------------------------------------------------------------------------#
module "s3_notifications" {
  source      = "terraform-aws-modules/s3-bucket/aws//modules/notification"
  for_each    = local.env.s3.bucket
  bucket      = module.s3[each.key].s3_bucket_id
  eventbridge = each.value.eventbridge
}
