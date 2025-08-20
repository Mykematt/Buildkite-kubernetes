#!/bin/bash

# Build and push custom multi-tool container to ECR
# This container has AWS CLI, kubectl, and Helm pre-installed

set -euo pipefail

# Configuration
AWS_REGION="us-east-1"
ECR_REPOSITORY="buildkite-multi-tool"
IMAGE_TAG="latest"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}"

echo "🏗️  Building custom multi-tool container..."
echo "Repository: ${ECR_URI}"

# Create ECR repository if it doesn't exist
echo "📦 Creating ECR repository if it doesn't exist..."
aws ecr describe-repositories --repository-names ${ECR_REPOSITORY} --region ${AWS_REGION} 2>/dev/null || \
aws ecr create-repository --repository-name ${ECR_REPOSITORY} --region ${AWS_REGION}

# Get ECR login token
echo "🔐 Logging into ECR..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Build the image
echo "🔨 Building Docker image..."
docker build -t ${ECR_REPOSITORY}:${IMAGE_TAG} .

# Tag for ECR
echo "🏷️  Tagging image for ECR..."
docker tag ${ECR_REPOSITORY}:${IMAGE_TAG} ${ECR_URI}:${IMAGE_TAG}

# Push to ECR
echo "⬆️  Pushing image to ECR..."
docker push ${ECR_URI}:${IMAGE_TAG}

echo "✅ Successfully pushed image to ECR!"
echo "Image URI: ${ECR_URI}:${IMAGE_TAG}"
echo ""
echo "You can now use this image in your Buildkite pipelines:"
echo "  image: \"${ECR_URI}:${IMAGE_TAG}\""
