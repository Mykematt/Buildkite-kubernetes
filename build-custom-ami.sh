#!/bin/bash
set -euo pipefail

# Build custom Buildkite AMI with Helm and kubectl pre-installed
# Uses user data script to install tools automatically

REGION="us-east-1"
BASE_AMI="ami-0188c0bf91f78660a"  # Current Buildkite Elastic Stack AMI
INSTANCE_TYPE="t3.medium"

echo "🚀 Building custom Buildkite AMI with Helm and kubectl..."

# Create user data script for installing tools
cat > user-data.sh << 'EOF'
#!/bin/bash
set -euo pipefail

# Log all output
exec > >(tee /var/log/user-data.log) 2>&1

echo "🔧 Installing Helm and kubectl..."

# Install kubectl
echo "Installing kubectl..."
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# Install Helm
echo "Installing Helm..."
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
sudo ./get_helm.sh

# Verify installations
echo "✅ Verifying installations..."
kubectl version --client
helm version

# Create completion marker
echo "🎉 Tools installed successfully!" > /tmp/installation-complete

echo "Installation completed at $(date)"
EOF

# Base64 encode the user data script
USER_DATA=$(base64 -i user-data.sh)

# Create temporary instance from base AMI with user data
echo "📦 Launching temporary instance with installation script..."
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $BASE_AMI \
    --instance-type $INSTANCE_TYPE \
    --region $REGION \
    --user-data "$USER_DATA" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=buildkite-custom-ami-builder}]' \
    --query 'Instances[0].InstanceId' \
    --output text)

echo "🔄 Waiting for instance $INSTANCE_ID to be running..."
aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region $REGION

echo "⏳ Waiting for tools installation to complete (5 minutes)..."
echo "   Instance ID: $INSTANCE_ID"
echo "   You can check /var/log/user-data.log on the instance for progress"

# Wait for installation to complete
sleep 300

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

# Clean up temporary files
rm -f user-data.sh

echo "✅ Custom AMI created successfully!"
echo "📋 AMI Details:"
echo "   AMI ID: $NEW_AMI_ID"
echo "   Name: $AMI_NAME"
echo "   Region: $REGION"

# Save AMI ID for next step
echo $NEW_AMI_ID > new-ami-id.txt
echo "💾 AMI ID saved to new-ami-id.txt"

echo ""
echo "🔄 Next steps:"
echo "1. Update CloudFormation stack to use new AMI: $NEW_AMI_ID"
echo "2. Remove Helm installation steps from pipeline"
echo "3. Test simplified pipeline"
