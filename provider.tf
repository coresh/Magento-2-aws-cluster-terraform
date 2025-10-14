

//////////////////////////////////////////////////////////[ PROVIDER ]////////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Define provider
# # ---------------------------------------------------------------------------------------------------------------------#
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.16.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.7.2"
    }
  }
}
provider "aws" {
  default_tags {
   tags = local.default_tags
 }
}
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
  default_tags {
   tags = local.default_tags
 }
}
