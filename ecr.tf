

/////////////////////////////////////////////////////[ AWS ECR REPOSITORY ]///////////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create ecr repository
# # ---------------------------------------------------------------------------------------------------------------------#
module "ecr" {
  source            = "terraform-aws-modules/ecr/aws"
  version           = "3.1.1"
  create            = true
  create_repository = true
  repository_type   = "private"
  repository_name   = "${local.project}-images"
  repository_image_tag_mutability    = "MUTABLE"
  repository_image_scan_on_push      = true
  repository_force_delete            = true
  create_repository_policy           = true
  attach_repository_policy           = true
  repository_lambda_read_access_arns = [module.imgproxy.lambda_function_arn]
  create_lifecycle_policy            = true
  repository_lifecycle_policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      action = {
        type = "expire"
      }
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
    }]
  })
  tags = {
    Name = "${local.project}-images"
  }
}
