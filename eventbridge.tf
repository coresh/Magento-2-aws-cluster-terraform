


////////////////////////////////////////////////////////[ EVENTBRIDGE RULES ]/////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create EventBridge service triggers
# # ---------------------------------------------------------------------------------------------------------------------#

module "eventbridge" {
  create     = true
  source     = "terraform-aws-modules/eventbridge/aws"
  version    =  "4.2.1"
  create_bus = false
  bus_name   = "default"


  create_role = true
  role_name   = "${local.project}-EventBridgeServiceRole"
  role_description = "Provides EventBridge manage events on your behalf."
  
  attach_sqs_policy = true
  sqs_target_arns   = [module.sqs.queue_arn]
  
  attach_policy_statements = true
  policy_statements = {
    ssm_automation = {
      effect = "Allow"
      actions = [
        "ssm:StartAutomationExecution",
        "sqs:SendMessage"
      ]
      resources = ["*"]
    }
  }

  rules = {
    "s3_ec2_config_update" = {
      description = "Trigger SSM document when s3 system bucket ec2_config updated"
      event_pattern = jsonencode({
        "source"      : ["aws.s3"],
        "detail-type" : ["Object Created"],
        "detail"      : {
          "bucket" : { "name" : [module.s3["system"].s3_bucket_id] },
          "object" : { "key" : [{ "prefix" : "ec2_config/" }] }
        }
      })
      enabled = true
      role_arn = true
    }
    "s3_release_update" = {
      description = "Trigger SSM document when s3 system bucket release updated"
      event_pattern = jsonencode({
        "source"      : ["aws.s3"],
        "detail-type" : ["Object Created"],
        "detail"      : {
          "bucket" : { "name" : [module.s3["system"].s3_bucket_id] },
          "object" : { "key" : [{ "prefix" : "releases/" }] }
        }
      })
      enabled = true
      role_arn = true
    }
  }

  targets = {
    "s3_ec2_config_update" = [
      {
	    name            = "${local.project}-s3-ec2-config-update"
        arn             = aws_ssm_document.ec2_config.arn
        attach_role_arn = true
        
        dead_letter_config = {
          arn = module.sqs.queue_arn
        }
        
        input_transformer = {
          input_paths = {
            S3ObjectKey = "$.detail.object.key"
          }
          input_template = <<END
{
  "S3ObjectKey": ["<S3ObjectKey>"]
}
END
        }
      }
    ]
    "s3_release_update" = [
      {
	    name            = "${local.project}-s3-release-update"
        arn             = aws_ssm_document.release.arn
        attach_role_arn = true
        
        dead_letter_config = {
          arn = module.sqs.queue_arn
        }
        
        input_transformer = {
          input_paths = {
            S3ObjectKey = "$.detail.object.key"
          }
          input_template = <<END
{
  "S3ObjectKey": ["<S3ObjectKey>"]
}
END
        }
      }
    ]
  }

  append_rule_postfix = false
  create_rules        = true
  create_targets      = true

  depends_on = [module.autoscaling]
}