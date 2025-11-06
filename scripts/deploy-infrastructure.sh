#!/bin/bash

# Deploy Infrastructure Script for NestJS ECS Application
# This script deploys the CloudFormation stacks in the correct order

set -e

# Configuration
ENVIRONMENT_NAME=${ENVIRONMENT_NAME:-nestjs-prod}
AWS_REGION=${AWS_REGION:-us-east-1}
S3_BUCKET=${S3_BUCKET:-""}

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

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo_error "AWS CLI is not installed. Please install it first."
    exit 1
fi

# Check if S3 bucket is provided for master stack
if [ -n "$USE_MASTER_STACK" ] && [ -z "$S3_BUCKET" ]; then
    echo_error "S3_BUCKET environment variable must be set when using master stack"
    exit 1
fi

# Function to wait for stack completion
wait_for_stack() {
    local stack_name=$1
    local operation=$2

    echo_info "Waiting for stack $stack_name to complete..."

    if [ "$operation" = "create" ]; then
        aws cloudformation wait stack-create-complete \
            --stack-name "$stack_name" \
            --region "$AWS_REGION"
    else
        aws cloudformation wait stack-update-complete \
            --stack-name "$stack_name" \
            --region "$AWS_REGION"
    fi

    if [ $? -eq 0 ]; then
        echo_info "Stack $stack_name completed successfully"
    else
        echo_error "Stack $stack_name failed"
        exit 1
    fi
}

# Function to deploy a stack
deploy_stack() {
    local stack_name=$1
    local template_file=$2
    local parameters=$3

    echo_info "Deploying stack: $stack_name"

    # Check if stack exists
    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$AWS_REGION" &> /dev/null

    if [ $? -eq 0 ]; then
        echo_info "Stack exists, updating..."
        aws cloudformation update-stack \
            --stack-name "$stack_name" \
            --template-body "file://$template_file" \
            --parameters "$parameters" \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$AWS_REGION" 2>&1 | tee /tmp/update-output.txt

        if grep -q "No updates are to be performed" /tmp/update-output.txt; then
            echo_info "No updates needed for $stack_name"
        else
            wait_for_stack "$stack_name" "update"
        fi
    else
        echo_info "Stack does not exist, creating..."
        aws cloudformation create-stack \
            --stack-name "$stack_name" \
            --template-body "file://$template_file" \
            --parameters "$parameters" \
            --capabilities CAPABILITY_NAMED_IAM \
            --region "$AWS_REGION"

        wait_for_stack "$stack_name" "create"
    fi
}

# Deploy stacks in order
echo_info "Starting infrastructure deployment for environment: $ENVIRONMENT_NAME"

# 1. Deploy VPC Stack
deploy_stack \
    "${ENVIRONMENT_NAME}-vpc-stack" \
    "cloudformation/01-vpc.yaml" \
    "ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT_NAME"

# 2. Deploy ECR Stack
deploy_stack \
    "${ENVIRONMENT_NAME}-ecr-stack" \
    "cloudformation/02-ecr.yaml" \
    "ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT_NAME"

# 3. Deploy ALB Stack
deploy_stack \
    "${ENVIRONMENT_NAME}-alb-stack" \
    "cloudformation/03-alb.yaml" \
    "ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT_NAME"

# 4. Deploy ECS Stack (requires ECR to be deployed first for initial image)
echo_warn "NOTE: ECS stack will be deployed with 'latest' image tag."
echo_warn "Make sure to push an initial Docker image before deploying ECS stack."
read -p "Continue with ECS stack deployment? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo_info "Skipping ECS stack deployment. Deploy it manually after pushing Docker image."
    exit 0
fi

deploy_stack \
    "${ENVIRONMENT_NAME}-ecs-stack" \
    "cloudformation/04-ecs.yaml" \
    "ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT_NAME ParameterKey=ImageTag,ParameterValue=latest"

# Get outputs
echo_info "Deployment completed successfully!"
echo_info "Fetching stack outputs..."

ALB_URL=$(aws cloudformation describe-stacks \
    --stack-name "${ENVIRONMENT_NAME}-alb-stack" \
    --query "Stacks[0].Outputs[?OutputKey=='LoadBalancerUrl'].OutputValue" \
    --output text \
    --region "$AWS_REGION")

ECR_URI=$(aws cloudformation describe-stacks \
    --stack-name "${ENVIRONMENT_NAME}-ecr-stack" \
    --query "Stacks[0].Outputs[?OutputKey=='ECRRepositoryUri'].OutputValue" \
    --output text \
    --region "$AWS_REGION")

echo_info "Application URL: http://$ALB_URL"
echo_info "ECR Repository: $ECR_URI"
