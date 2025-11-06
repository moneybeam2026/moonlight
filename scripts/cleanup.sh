#!/bin/bash

# Cleanup Script - Deletes all CloudFormation stacks

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

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_warn "This will delete all infrastructure for environment: $ENVIRONMENT_NAME"
echo_warn "This action cannot be undone!"
read -p "Are you sure you want to continue? (type 'yes' to confirm) " -r
echo

if [[ ! $REPLY = "yes" ]]; then
    echo_info "Cleanup cancelled"
    exit 0
fi

# Function to delete stack
delete_stack() {
    local stack_name=$1

    echo_info "Checking if stack $stack_name exists..."

    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$AWS_REGION" &> /dev/null

    if [ $? -eq 0 ]; then
        echo_info "Deleting stack: $stack_name"
        aws cloudformation delete-stack \
            --stack-name "$stack_name" \
            --region "$AWS_REGION"

        echo_info "Waiting for stack deletion..."
        aws cloudformation wait stack-delete-complete \
            --stack-name "$stack_name" \
            --region "$AWS_REGION"

        echo_info "Stack $stack_name deleted successfully"
    else
        echo_info "Stack $stack_name does not exist, skipping"
    fi
}

# Delete ECR images first
echo_info "Deleting ECR images..."
ECR_REPO=$(aws cloudformation describe-stacks \
    --stack-name "${ENVIRONMENT_NAME}-ecr-stack" \
    --query "Stacks[0].Outputs[?OutputKey=='ECRRepositoryName'].OutputValue" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo "")

if [ -n "$ECR_REPO" ]; then
    aws ecr batch-delete-image \
        --repository-name "$ECR_REPO" \
        --image-ids "$(aws ecr list-images --repository-name "$ECR_REPO" --query 'imageIds[*]' --output json)" \
        --region "$AWS_REGION" 2>/dev/null || true
fi

# Delete stacks in reverse order
delete_stack "${ENVIRONMENT_NAME}-ecs-stack"
delete_stack "${ENVIRONMENT_NAME}-alb-stack"
delete_stack "${ENVIRONMENT_NAME}-ecr-stack"
delete_stack "${ENVIRONMENT_NAME}-vpc-stack"

echo_info "All stacks deleted successfully!"
