#!/bin/bash
set -euo pipefail

# Update ola-buildkite-v2 CloudFormation stack with new custom AMI

STACK_NAME="ola-buildkite-v2"
REGION="us-east-1"

# Check if new AMI ID file exists
if [[ ! -f "new-ami-id.txt" ]]; then
    echo "❌ new-ami-id.txt not found. Run build-custom-ami.sh first."
    exit 1
fi

NEW_AMI_ID=$(cat new-ami-id.txt)
echo "🔄 Updating CloudFormation stack with new AMI: $NEW_AMI_ID"

# Get current stack parameters
echo "📋 Getting current stack parameters..."
CURRENT_PARAMS=$(aws cloudformation describe-stacks \
    --stack-name $STACK_NAME \
    --region $REGION \
    --query 'Stacks[0].Parameters' \
    --output json)

# Update ImageIdParameter while preserving other parameters
echo "🔧 Updating ImageIdParameter..."
UPDATED_PARAMS=$(echo "$CURRENT_PARAMS" | jq --arg new_ami "$NEW_AMI_ID" '
    map(if .ParameterKey == "ImageIdParameter" then .ParameterValue = $new_ami else . end)
')

# Convert to CloudFormation parameter format (use file instead of inline)
echo "$UPDATED_PARAMS" > stack-parameters.json

echo "🚀 Updating CloudFormation stack..."
aws cloudformation update-stack \
    --stack-name $STACK_NAME \
    --region $REGION \
    --use-previous-template \
    --parameters file://stack-parameters.json \
    --capabilities CAPABILITY_NAMED_IAM

echo "⏳ Waiting for stack update to complete..."
aws cloudformation wait stack-update-complete \
    --stack-name $STACK_NAME \
    --region $REGION

echo "✅ Stack updated successfully!"
echo "📋 New AMI ID: $NEW_AMI_ID"

echo ""
echo "🔄 Next steps:"
echo "1. Wait for new agents to launch with updated AMI"
echo "2. Update pipeline to remove Helm installation steps"
echo "3. Test simplified pipeline"
