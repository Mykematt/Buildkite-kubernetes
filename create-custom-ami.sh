#!/bin/bash
set -euo pipefail

# Build custom Buildkite AMI with Helm and kubectl pre-installed
# Uses AWS Systems Manager to avoid SSH requirements

REGION="us-east-1"
BASE_AMI="ami-0188c0bf91f78660a"  # Current Buildkite Elastic Stack AMI
INSTANCE_TYPE="t3.medium"

echo "🚀 Building custom Buildkite AMI with Helm and kubectl..."

# Create temporary instance from base AMI
echo "📦 Launching temporary instance from base AMI..."
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $BASE_AMI \
    --instance-type $INSTANCE_TYPE \
    --region $REGION \
    --iam-instance-profile Name=EC2InstanceProfileForImageBuilder \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=buildkite-custom-ami-builder}]' \
    --query 'Instances[0].InstanceId' \
    --output text)

echo "🔄 Waiting for instance $INSTANCE_ID to be running..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region $REGION

# Wait for Systems Manager agent to be ready
echo "⏳ Waiting for Systems Manager agent..."
sleep 60

# Install kubectl and Helm using Systems Manager
echo "🔧 Installing kubectl via Systems Manager..."
aws ssm send-command \
    --instance-ids $INSTANCE_ID \
    --document-name "AWS-RunShellScript" \
    --region $REGION \
    --parameters 'commands=[
        "curl -LO \"https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl\"",
        "chmod +x kubectl",
        "sudo mv kubectl /usr/local/bin/",
        "kubectl version --client"
    ]' \
    --query 'Command.CommandId' \
    --output text > kubectl_command_id.txt

echo "🔧 Installing Helm via Systems Manager..."
aws ssm send-command \
    --instance-ids $INSTANCE_ID \
    --document-name "AWS-RunShellScript" \
    --region $REGION \
    --parameters 'commands=[
        "curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3",
        "chmod 700 get_helm.sh",
        "sudo ./get_helm.sh",
        "helm version"
    ]' \
    --query 'Command.CommandId' \
    --output text > helm_command_id.txt

# Wait for commands to complete
echo "⏳ Waiting for installation commands to complete..."
sleep 120

# Verify installations
echo "✅ Verifying installations..."
aws ssm send-command \
    --instance-ids $INSTANCE_ID \
    --document-name "AWS-RunShellScript" \
    --region $REGION \
    --parameters 'commands=[
        "echo \"=== kubectl version ===\"",
        "kubectl version --client",
        "echo \"=== helm version ===\"", 
        "helm version",
        "echo \"=== Installation complete ===\""
    ]' \
    --query 'Command.CommandId' \
    --output text > verify_command_id.txt

sleep 30

# Create AMI from the instance
echo "📸 Creating AMI from configured instance..."
AMI_NAME="buildkite-stack-helm-kubectl-$(date +%Y-%m-%d-%H-%M-%S)"
NEW_AMI_ID=$(aws ec2 create-image \
    --instance-id $INSTANCE_ID \
    --name "$AMI_NAME" \
    --description "Buildkite Elastic Stack (Amazon Linux 2023) with Helm and kubectl pre-installed" \
    --region $REGION \
    --query 'ImageId' \
    --output text)

echo "🔄 Creating AMI: $NEW_AMI_ID"
echo "⏳ Waiting for AMI to be available..."
aws ec2 wait image-available --image-ids $NEW_AMI_ID --region $REGION

# Terminate the temporary instance
echo "🧹 Cleaning up temporary instance..."
aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region $REGION

# Clean up command ID files
rm -f kubectl_command_id.txt helm_command_id.txt verify_command_id.txt

echo "✅ Custom AMI created successfully!"
echo "📋 AMI Details:"
echo "   AMI ID: $NEW_AMI_ID"
echo "   Name: $AMI_NAME"
echo "   Region: $REGION"

echo ""
echo "🔄 Next steps:"
echo "1. Update CloudFormation stack to use new AMI: $NEW_AMI_ID"
echo "2. Remove Helm installation steps from pipeline"
echo "3. Test simplified pipeline"

# Save AMI ID for next step
echo $NEW_AMI_ID > new-ami-id.txt
echo "💾 AMI ID saved to new-ami-id.txt"
