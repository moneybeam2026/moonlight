#!/bin/bash

# Update ECS Service Script
# Forces a new deployment of the ECS service

set -e

# Configuration
ENVIRONMENT_NAME=${ENVIRONMENT_NAME:-nestjs-prod}
AWS_REGION=${AWS_REGION:-us-east-1}

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

# Get cluster and service names
echo_info "Fetching ECS cluster and service names..."

CLUSTER_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${ENVIRONMENT_NAME}-ecs-stack" \
    --query "Stacks[0].Outputs[?OutputKey=='ECSCluster'].OutputValue" \
    --output text \
    --region "$AWS_REGION")

SERVICE_NAME=$(aws cloudformation describe-stacks \
    --stack-name "${ENVIRONMENT_NAME}-ecs-stack" \
    --query "Stacks[0].Outputs[?OutputKey=='ECSService'].OutputValue" \
    --output text \
    --region "$AWS_REGION")

if [ -z "$CLUSTER_NAME" ] || [ -z "$SERVICE_NAME" ]; then
    echo_error "ECS cluster or service not found. Please deploy infrastructure first."
    exit 1
fi

echo_info "Cluster: $CLUSTER_NAME"
echo_info "Service: $SERVICE_NAME"

# Force new deployment
echo_info "Forcing new deployment..."
aws ecs update-service \
    --cluster "$CLUSTER_NAME" \
    --service "$SERVICE_NAME" \
    --force-new-deployment \
    --region "$AWS_REGION" > /dev/null

# Wait for service to stabilize
echo_info "Waiting for service to stabilize (this may take a few minutes)..."
aws ecs wait services-stable \
    --cluster "$CLUSTER_NAME" \
    --services "$SERVICE_NAME" \
    --region "$AWS_REGION"

echo_info "Service updated successfully!"

# Get application URL
ALB_URL=$(aws cloudformation describe-stacks \
    --stack-name "${ENVIRONMENT_NAME}-alb-stack" \
    --query "Stacks[0].Outputs[?OutputKey=='LoadBalancerUrl'].OutputValue" \
    --output text \
    --region "$AWS_REGION")

echo_info "Application URL: http://$ALB_URL"
