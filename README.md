# NestJS AWS ECS Deployment

Complete infrastructure-as-code setup for deploying a NestJS application to AWS ECS using Docker and CloudFormation.

## Architecture Overview

This project deploys a containerized NestJS application on AWS with the following components:

- **VPC**: Custom VPC with public and private subnets across 2 availability zones
- **Application Load Balancer**: Internet-facing ALB in public subnets
- **ECS Fargate**: Container orchestration with tasks running in private subnets
- **ECR**: Private Docker registry for application images
- **Auto Scaling**: CPU and memory-based auto scaling (2-10 tasks)
- **CloudWatch**: Centralized logging with 30-day retention

## Project Structure

```
.
├── src/                          # NestJS application source code
├── cloudformation/               # Infrastructure templates
│   ├── 01-vpc.yaml              # VPC and networking
│   ├── 02-ecr.yaml              # ECR repository
│   ├── 03-alb.yaml              # Load balancer and security groups
│   ├── 04-ecs.yaml              # ECS cluster and services
│   └── master.yaml              # Master orchestration stack
├── scripts/                      # Deployment scripts
│   ├── deploy-infrastructure.sh # Deploy all CloudFormation stacks
│   ├── build-and-push.sh        # Build and push Docker image
│   ├── update-service.sh        # Force ECS service update
│   └── cleanup.sh               # Delete all infrastructure
├── .github/workflows/            # CI/CD pipelines
│   └── deploy.yml               # GitHub Actions deployment
├── Dockerfile                    # Multi-stage Docker build
└── package.json                  # Node.js dependencies
```

## Prerequisites

Before you begin, ensure you have:

1. **AWS Account** with appropriate permissions
2. **AWS CLI** installed and configured
   ```bash
   aws configure
   ```
3. **Docker** installed (for local builds)
4. **Node.js 18+** (for local development)
5. **Git** repository (for CI/CD)

## Quick Start

### Step 1: Configure Environment

Set your environment variables:

```bash
export ENVIRONMENT_NAME=nestjs-prod
export AWS_REGION=us-east-1
```

### Step 2: Deploy Infrastructure

Deploy all CloudFormation stacks in the correct order:

```bash
./scripts/deploy-infrastructure.sh
```

This will create:
- VPC with public/private subnets
- NAT Gateways for private subnet internet access
- Application Load Balancer
- ECR repository
- ECS cluster (deployment paused until Docker image is available)

### Step 3: Build and Push Docker Image

Build your application and push to ECR:

```bash
./scripts/build-and-push.sh
```

### Step 4: Complete ECS Deployment

If you skipped the ECS deployment in step 2, deploy it now:

```bash
aws cloudformation create-stack \
  --stack-name ${ENVIRONMENT_NAME}-ecs-stack \
  --template-body file://cloudformation/04-ecs.yaml \
  --parameters ParameterKey=EnvironmentName,ParameterValue=$ENVIRONMENT_NAME \
               ParameterKey=ImageTag,ParameterValue=latest \
  --capabilities CAPABILITY_NAMED_IAM \
  --region $AWS_REGION
```

### Step 5: Access Your Application

Get the application URL:

```bash
aws cloudformation describe-stacks \
  --stack-name ${ENVIRONMENT_NAME}-alb-stack \
  --query "Stacks[0].Outputs[?OutputKey=='LoadBalancerUrl'].OutputValue" \
  --output text
```

Visit `http://<load-balancer-url>` in your browser.

## GitHub Actions CI/CD

### Setup

1. Add the following secrets to your GitHub repository:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`

2. Update the workflow environment variables in `.github/workflows/deploy.yml`:
   ```yaml
   env:
     AWS_REGION: us-east-1        # Your AWS region
     ENVIRONMENT_NAME: nestjs-prod # Your environment name
   ```

### Automatic Deployment

The workflow automatically triggers on:
- Push to `main` branch
- Manual workflow dispatch

The pipeline will:
1. Build Docker image
2. Push to ECR with commit SHA and `latest` tags
3. Update ECS task definition
4. Deploy new version with zero-downtime
5. Wait for service to stabilize

## Manual Deployment

### Update Service with New Code

After making code changes:

```bash
# Build and push new image
./scripts/build-and-push.sh

# Force service update
./scripts/update-service.sh
```

### Deploy with Specific Image Tag

```bash
export IMAGE_TAG=v1.2.3
./scripts/build-and-push.sh
./scripts/update-service.sh
```

## Configuration

### Environment Variables

Edit the CloudFormation parameters in `cloudformation/04-ecs.yaml`:

- `DesiredCount`: Number of tasks (default: 2)
- `ContainerCpu`: CPU units per task (default: 256)
- `ContainerMemory`: Memory per task in MB (default: 512)

### Auto Scaling

Auto scaling is configured in `cloudformation/04-ecs.yaml`:

- **CPU Target**: 70%
- **Memory Target**: 80%
- **Min Tasks**: 2
- **Max Tasks**: 10

### Custom Domain and HTTPS

To add a custom domain with HTTPS:

1. Create an ACM certificate in your region
2. Update `cloudformation/03-alb.yaml` to add HTTPS listener:

```yaml
HTTPSListener:
  Type: AWS::ElasticLoadBalancingV2::Listener
  Properties:
    LoadBalancerArn: !Ref ApplicationLoadBalancer
    Port: 443
    Protocol: HTTPS
    Certificates:
      - CertificateArn: arn:aws:acm:region:account:certificate/xxx
    DefaultActions:
      - Type: forward
        TargetGroupArn: !Ref TargetGroup
```

3. Add Route53 record pointing to the ALB

## Monitoring and Logs

### View Application Logs

```bash
aws logs tail /ecs/${ENVIRONMENT_NAME} --follow
```

### CloudWatch Metrics

View metrics in AWS Console:
- ECS Console → Clusters → Your Cluster → Metrics
- CloudWatch → Metrics → ECS

### Health Check

The application exposes a health endpoint at `/health` that returns:

```json
{
  "status": "ok",
  "timestamp": "2025-11-06T12:00:00.000Z"
}
```

## Cost Optimization

### Estimated Monthly Costs (us-east-1)

- **VPC & Networking**:
  - NAT Gateways (2): ~$65/month ($32.40/gateway)
  - Data transfer: ~$10-50/month (depending on usage)
- **ECS Fargate**:
  - 2 tasks @ 0.25 vCPU, 0.5 GB: ~$15/month
  - Auto scaling overhead: ~$10-30/month
- **Application Load Balancer**: ~$20/month
- **ECR Storage**: ~$1/month (for a few GB)
- **CloudWatch Logs**: ~$5/month (for moderate logging)

**Total**: ~$125-180/month

### Reduce Costs

1. **Use single NAT Gateway**:
   - Modify `cloudformation/01-vpc.yaml` to use one NAT Gateway
   - **Saves**: ~$32/month
   - **Risk**: Reduced availability if NAT Gateway fails

2. **Use Fargate Spot**:
   - Already configured in capacity provider strategy
   - Can save up to 70% on compute costs

3. **Reduce task count**:
   - Set `DesiredCount: 1` for dev environments
   - Use smaller CPU/memory allocations

## Troubleshooting

### ECS Tasks Not Starting

Check ECS service events:
```bash
aws ecs describe-services \
  --cluster ${ENVIRONMENT_NAME}-cluster \
  --services ${ENVIRONMENT_NAME}-service \
  --query "services[0].events[0:5]"
```

### Common Issues

1. **Task fails health check**: Ensure `/health` endpoint responds with 200
2. **Cannot pull image**: Check ECR permissions and image exists
3. **Out of memory**: Increase `ContainerMemory` parameter
4. **Slow startup**: Increase health check grace period

### View Task Logs

```bash
# Get task ARN
TASK_ARN=$(aws ecs list-tasks \
  --cluster ${ENVIRONMENT_NAME}-cluster \
  --service-name ${ENVIRONMENT_NAME}-service \
  --query "taskArns[0]" --output text)

# View logs
aws logs get-log-events \
  --log-group-name /ecs/${ENVIRONMENT_NAME} \
  --log-stream-name ecs/${ENVIRONMENT_NAME}-container/${TASK_ARN##*/}
```

## Cleanup

To delete all infrastructure:

```bash
./scripts/cleanup.sh
```

This will delete all CloudFormation stacks and ECR images. You will be prompted to confirm.

## Security Best Practices

1. **Use Secrets Manager**: Store sensitive data (API keys, DB passwords) in AWS Secrets Manager
2. **Enable VPC Flow Logs**: Monitor network traffic for security analysis
3. **Implement WAF**: Add AWS WAF rules to protect against common attacks
4. **Use Private Subnets**: Tasks run in private subnets with no direct internet access
5. **Least Privilege IAM**: Task roles have minimal required permissions
6. **Enable ECR Scanning**: Images are automatically scanned for vulnerabilities

## Development

### Local Development

```bash
# Install dependencies
npm install

# Run in development mode
npm run start:dev

# Build
npm run build

# Run production build
npm run start:prod
```

### Test Docker Build Locally

```bash
docker build -t nestjs-app .
docker run -p 3000:3000 nestjs-app
```

Visit `http://localhost:3000`

## Next Steps

1. **Add Database**: Integrate RDS, DynamoDB, or other data stores
2. **Implement Caching**: Add ElastiCache for Redis or Memcached
3. **Set Up Monitoring**: Configure CloudWatch alarms and dashboards
4. **Enable HTTPS**: Add SSL/TLS certificate and custom domain
5. **Implement Authentication**: Add Cognito or OAuth integration
6. **Add CI/CD Tests**: Include unit/integration tests in pipeline
7. **Multi-Environment**: Duplicate setup for dev/staging/production

## Support

For issues or questions:
- Check AWS CloudFormation events for detailed error messages
- Review ECS service events and task logs
- Verify IAM permissions and security group rules

## License

MIT
