#!/bin/bash

# Build and Push Docker Image Script

set -e

# Configuration
ENVIRONMENT_NAME=${ENVIRONMENT_NAME:-nestjs-prod}
AWS_REGION=${AWS_REGION:-us-east-1}
IMAGE_TAG=${IMAGE_TAG:-latest}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo_error "Docker is not installed. Please install it first."
    exit 1
fi

# Get ECR repository URI
echo_info "Fetching ECR repository URI..."
ECR_URI=$(aws cloudformation describe-stacks \
    --stack-name "${ENVIRONMENT_NAME}-ecr-stack" \
    --query "Stacks[0].Outputs[?OutputKey=='ECRRepositoryUri'].OutputValue" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null)

if [ -z "$ECR_URI" ]; then
    echo_error "ECR repository not found. Please deploy infrastructure first."
    exit 1
fi

echo_info "ECR Repository: $ECR_URI"

# Login to ECR
echo_info "Logging in to Amazon ECR..."
aws ecr get-login-password --region "$AWS_REGION" | \
    docker login --username AWS --password-stdin "$ECR_URI"

# Build Docker image
echo_info "Building Docker image..."
docker build -t "$ECR_URI:$IMAGE_TAG" .

# Tag as latest
if [ "$IMAGE_TAG" != "latest" ]; then
    docker tag "$ECR_URI:$IMAGE_TAG" "$ECR_URI:latest"
fi

# Push to ECR
echo_info "Pushing image to ECR..."
docker push "$ECR_URI:$IMAGE_TAG"

if [ "$IMAGE_TAG" != "latest" ]; then
    docker push "$ECR_URI:latest"
fi

echo_info "Successfully pushed image: $ECR_URI:$IMAGE_TAG"
