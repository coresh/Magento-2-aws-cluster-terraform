

///////////////////////////////////////////////////////[ DATA RESOURCES ]/////////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Define data resources
# # ---------------------------------------------------------------------------------------------------------------------#
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_ami" "this" {
  most_recent = true
  owners      = ["136693071363"]
  filter {
    name   = "name"
    values = ["debian-13-arm64*"]
  }
}
data "aws_ami" "ecs_optimized" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-ecs-*"]
  }
  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}
