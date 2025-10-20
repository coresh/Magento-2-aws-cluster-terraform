


/////////////////////////////////////////////////////[ SQS DEAD LETTER QUEUE ]////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create SQS queue to collect failed events debug messages
# # ---------------------------------------------------------------------------------------------------------------------#

module "sqs" {
  source = "terraform-aws-modules/sqs/aws"
  version = "5.0.0"
  create = true
  name                      = "${local.project}-dead-letter-queue"
  delay_seconds             = 5
  max_message_size          = 262144
  message_retention_seconds = 1209600
  receive_wait_time_seconds = 5
  create_dlq = false
}