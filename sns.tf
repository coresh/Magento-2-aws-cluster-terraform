

/////////////////////////////////////////////////////[ SNS TOPICS MODULE ]////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create SNS topics for alerts subscription
# # ---------------------------------------------------------------------------------------------------------------------#
module "sns" {
  source   = "terraform-aws-modules/sns/aws"
  version  = "6.2.0"
  for_each = local.env.sns.topic
  name     = "${local.project}-${each.key}"
  subscriptions = {
    for email_address in each.value.email :
    "email" => {
      protocol = "email"
      endpoint = email_address
    }
  }
}
