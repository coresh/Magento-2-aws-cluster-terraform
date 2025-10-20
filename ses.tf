


////////////////////////////////////////////////////[ AMAZON SIMPLE EMAIL SERVICE ]///////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create SES user credentials, Configuration Set to stream SES metrics to CloudWatch
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_iam_user" "smtp" {
  name = "${local.project}-ses-smtp-user"
}
	

resource "aws_ses_domain_identity" "domain" {
  domain = local.env.domain
}

resource "aws_iam_user_policy" "smtp_policy" {
  name = "${local.project}-ses-smtp-user-policy"
  user = aws_iam_user.smtp.name
  
  policy = jsonencode({
    Version : "2012-10-17",
    Statement : [
      {
        Effect : "Allow",
        Action : [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ],
        Resource : "*"
      }
    ]
  })
}

resource "aws_iam_access_key" "smtp" {
  user = aws_iam_user.smtp.name
}

resource "aws_ses_configuration_set" "this" {
  name = "${local.project}-ses-events"
  reputation_metrics_enabled = true
  delivery_options {
    tls_policy = "Require"
  }
}

resource "aws_ses_event_destination" "cloudwatch" {
  name                   = "${local.project}-ses-event-destination-cloudwatch"
  configuration_set_name = aws_ses_configuration_set.this.name
  enabled                = true
  matching_types         = ["bounce", "send", "complaint", "delivery"]

  cloudwatch_destination {
    default_value  = "default"
    dimension_name = "dimension"
    value_source   = "emailHeader"
  }
}