



////////////////////////////////////////[ SYSTEM MANAGER DOCUMENT EC2 INITIALIZATION ]////////////////////////////////////

# # ---------------------------------------------------------------------------------------------------------------------#
# Create SSM Document association with Auto Scaling Group
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_ssm_association" "ec2_init" {
  for_each = local.env.ec2
  name     = aws_ssm_document.ec2_init.name
  targets {
    key    = "tag:aws:autoscaling:groupName"
    values = [module.autoscaling[each.key].autoscaling_group_name]
  }
  association_name = "EC2Init-for-${module.autoscaling[each.key].autoscaling_group_name}"
  document_version = "$LATEST"
  automation_target_parameter_name = "InstanceIds"
}
# # ---------------------------------------------------------------------------------------------------------------------#
# Create SSM Document to configure EC2 instances in Auto Scaling Group
# # ---------------------------------------------------------------------------------------------------------------------#
resource "aws_ssm_document" "ec2_init" {
  name            = "InstanceInitialization"
  document_format = "YAML"
  document_type   = "Automation"
  content = <<EOF
schemaVersion: "0.3"
description: "Instance initialization: install base packages"
assumeRole: ${aws_iam_role.ssm_service_role.arn}
parameters:
  InstanceIds:
    type: String
    description: The target instance id
mainSteps:
  - name: "WaitForInstanceStateRunning"
    action: "aws:waitForAwsResourceProperty"
    timeoutSeconds: 300
    isCritical: true
    inputs:
      Service: "ec2"
      Api: "DescribeInstanceStatus"
      InstanceIds:
        - "{{ InstanceIds }}"
      PropertySelector: "$.InstanceStatuses[0].InstanceState.Name"
      DesiredValues:
        - running
  - name: "AssertInstanceStateRunning"
    isCritical: true
    action: "aws:assertAwsResourceProperty"
    inputs:
      Service: "ec2"
      Api: "DescribeInstanceStatus"
      InstanceIds:
        - "{{ InstanceIds }}"
      PropertySelector: "$.InstanceStatuses[0].InstanceState.Name"
      DesiredValues:
        - "running"
  - name: "WaitForInstanceStatusOk"
    action: "aws:waitForAwsResourceProperty"
    timeoutSeconds: 300
    isCritical: true
    inputs:
      Service: "ec2"
      Api: "DescribeInstanceStatus"
      InstanceIds:
        - "{{ InstanceIds }}"
      PropertySelector: "$.InstanceStatuses[0].InstanceStatus.Status"
      DesiredValues:
        - "ok"
  - name: "WriteHelperScripts"
    action: "aws:runCommand"
    inputs:
      DocumentName: "AWS-RunShellScript"
      Parameters:
        commands:
          - |-
            ### Parameterstore request script
            cat <<'END' > /usr/local/bin/parameterstore
            #!/bin/bash
            parameterstore() {
                local KEY=$1
                local PARAMETER_NAME="/${local.project}/$${KEY}"
                sudo /root/awscli/bin/aws ssm get-parameter --name "$${PARAMETER_NAME}" --with-decryption --query 'Parameter.Value' --output text
            }
            if [ "$#" -eq 0 ]; then
                echo "Usage: $0 <parameter-key>"
                echo "Example: $0 BRAND"
                exit 1
            fi
            KEY=$1
            parameterstore "$${KEY}"
            END
            chmod +x /usr/local/bin/parameterstore
            ### EC2 Metadata Request Script
            cat <<'END' > /usr/local/bin/metadata
            #!/bin/bash
            METADATA_URL="http://169.254.169.254/latest"
            metadata() {
                local FIELD=$1
                TOKEN=$(curl -sSf -X PUT "$${METADATA_URL}/api/token" \
                    -H "X-aws-ec2-metadata-token-ttl-seconds: 300") || {
                    echo "Error: Unable to fetch token. Ensure IMDSv2 is enabled." >&2
                    exit 1
                }
                curl -sSf -X GET "$${METADATA_URL}/meta-data/$${FIELD}" \
                    -H "X-aws-ec2-metadata-token: $${TOKEN}" || {
                    echo "Error: Unable to fetch metadata for field $${FIELD}." >&2
                    exit 1
                }
            }
            if [ "$#" -eq 0 ]; then
                echo "Usage: $0 <metadata-field>"
                echo "Example: $0 instance-id"
                exit 1
            fi
            FIELD=$1
            metadata "$${FIELD}"
            END
            chmod +x /usr/local/bin/metadata
            ### Write leader instance script
            cat <<'END' > /usr/local/bin/leader
            INSTANCE_ID=$(metadata instance-id)
            LEADER_INSTANCE_ID=$(sudo /root/awscli/bin/aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${module.autoscaling["backend"].autoscaling_group_name} --region ${data.aws_region.current.region} --output json | \
              jq -r '.AutoScalingGroups[].Instances[] | select(.LifecycleState=="InService") | .InstanceId' | sort | head -1)
            [ "$${LEADER_INSTANCE_ID}" = "$${INSTANCE_ID}" ]
            END
            chmod +x /usr/local/bin/leader
      Targets:
        - Key: "InstanceIds"
          Values:
            - "{{ InstanceIds }}"
      CloudWatchOutputConfig:
        CloudWatchOutputEnabled: true
  - name: "InstallBasePackages"
    action: "aws:runCommand"
    inputs:
      DocumentName: "AWS-RunShellScript"
      Parameters:
        commands:
          - |-
            #!/bin/bash
            apt-get -qqy update
            apt-get -qqy install jq gnupg snmp syslog-ng-core unzip pipx
            . /etc/os-release
            # install awscli v2
            mkdir /tmp/awscli
            cd /tmp/awscli
            curl "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "awscliv2.zip"
            unzip awscliv2.zip
            bash ./aws/install
            sudo ./aws/install --bin-dir /root/awscli/bin --install-dir /root/awscli/awscli --update
            INSTANCE_NAME="$(metadata tags/instance/InstanceName)"
            hostnamectl set-hostname $${INSTANCE_NAME}.${local.env.brand}.internal
            if [ "$${INSTANCE_NAME}" = "backend" ]; then
              apt -qqy install ruby
              cd /tmp
              wget https://aws-codedeploy-${data.aws_region.current.region}.s3.amazonaws.com/latest/install
              chmod +x ./install
              ./install auto
            fi
            cd /tmp
            wget https://amazoncloudwatch-agent.s3.amazonaws.com/$${ID}/$(dpkg --print-architecture)/latest/amazon-cloudwatch-agent.deb
            dpkg -i amazon-cloudwatch-agent.deb
            /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c ssm:/cloudwatch-agent/amazon-cloudwatch-agent.json
      Targets:
        - Key: "InstanceIds"
          Values:
            - "{{ InstanceIds }}"
      CloudWatchOutputConfig:
        CloudWatchOutputEnabled: true
  - name: "InstanceConfiguration"
    action: "aws:runCommand"
    isCritical: true
    isEnd: false
    onFailure: Abort
    inputs:
      DocumentName: "AWS-RunShellScript"
      InstanceIds:
        - "{{ InstanceIds }}"
      Parameters:
        commands:
          - |-
            #!/bin/bash
            sudo pipx install ansible-core
            sudo /root/.local/bin/ansible localhost -m ping > /dev/null 2>&1 && echo "SUCCESS: Ansible ping worked!" || { echo "ERROR: Ansible ping failed!"; exit 1; }
            INSTANCE_NAME=$(metadata tags/instance/InstanceName)
            INSTANCE_IP=$(metadata local-ipv4)
            CONFIG_DIRECTORY="ec2_config"
            CONFIG_PATH="/opt/${local.env.brand}/ec2_config"
            INSTANCE_DIRECTORY="$${CONFIG_PATH}/$${INSTANCE_NAME}"
            mkdir -p "$${INSTANCE_DIRECTORY}"
            touch $${CONFIG_PATH}/init
            S3_OPTIONS="--quiet --exact-timestamps --delete"
            sudo /root/awscli/bin/aws s3 sync "s3://${module.s3["system"].s3_bucket_id}/$${CONFIG_DIRECTORY}/$${INSTANCE_NAME}" "$${INSTANCE_DIRECTORY}" $${S3_OPTIONS}
            sudo /root/.local/bin/ansible-playbook -i localhost -c local -e "SSM=True instance_name=$${INSTANCE_NAME} instance_ip=$${INSTANCE_IP}" -v  $${INSTANCE_DIRECTORY}/$${INSTANCE_NAME}.yml
      CloudWatchOutputConfig:
        CloudWatchLogGroupName: "${local.project}-InstanceConfiguration"
        CloudWatchOutputEnabled: true
  - name: "GetInstancePrivateIp"
    action: "aws:executeAwsApi"
    inputs:
      Service: "ec2"
      Api: "DescribeInstances"
      InstanceIds:
        - "{{ InstanceIds }}"
    outputs:
      - Name: "PrivateIp"
        Selector: "$.Reservations[0].Instances[0].PrivateIpAddress"
        Type: "String"
  - name: "SendExecutionLog"
    action: "aws:executeAwsApi"
    isEnd: true
    inputs:
      Service: "sns"
      Api: "Publish"
      TopicArn: "${module.sns["devops"].topic_arn}"
      Subject: "Instance {{ InstanceIds }} initialization for ${local.project}"
      Message: "Instance {{ InstanceIds }} with ip {{ GetInstancePrivateIp.PrivateIp }} initialization {{ automation:EXECUTION_ID }} completed at {{ global:DATE_TIME }}"
EOF
}
