


//////////////////////////////////////////////[ SYSTEM MANAGER DOCUMENT RELEASE ]/////////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create SSM Document to check and deploy latest release on EC2 from S3
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_ssm_document" "release" {
  name            = "LatestReleaseDeployment"
  document_type   = "Automation"
  document_format = "YAML"
  content = <<EOF
schemaVersion: "0.3"
description: "Trigger CodeBuild project when new release is uploaded to S3"
assumeRole: ${aws_iam_role.ssm_service_role.arn}
parameters:
  S3ObjectKey:
    type: String
    description: S3 object key of the release
mainSteps:
  - name: StartCodeBuild
    action: "aws:executeAwsApi"
    inputs:
      Service: codebuild
      Api: StartBuild
      projectName: ${aws_codebuild_project.this.name}
      artifactsOverride:
        type: NO_ARTIFACTS
      environmentVariablesOverride:
        - name: "S3_RELEASE_BUCKET_ID"
          value: module.s3["releases"].s3_bucket_id
        - name: "S3_RELEASE_OBJECT_KEY" 
          value: "{{ S3ObjectKey }}"
        - name: "EFS_SYSTEM_ID"
          value: module.efs.id
        - name: "PROJECT"
          value: local.project
    outputs:
      - Name: BuildId
        Selector: "$.build.id"
        Type: String
        
  - name: SendNotification
    action: "aws:executeAwsApi"
    inputs:
      Service: "sns"
      Api: "Publish"
      TopicArn: "${module.sns["devops"].topic_arn}"
      Subject: "CodeBuild deployment triggered for ${local.project}"
      Message: "CodeBuild project ${aws_codebuild_project.this.name} started for release {{ S3ObjectKey }} with Build ID {{ StartCodeBuild.BuildId }} at {{ global:DATE_TIME }}"
EOF
}

