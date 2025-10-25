

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
  ])
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
# Create S3 buckets
# # ---------------------------------------------------------------------------------------------------------------------#
module "s3" {
  source   = "terraform-aws-modules/s3-bucket/aws"
  version  = "5.8.1"
  for_each = local.env.s3.bucket
  bucket   = "${local.project}-${each.key}"
  acl      = "private"
  #attach_policy           = true
  #policy                  = each.value.policy
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
  source   = "terraform-aws-modules/s3-bucket/aws//modules/notification"
  for_each = local.env.s3.bucket
  bucket   = module.s3[each.key].s3_bucket_id
  eventbridge = each.value.eventbridge
}
