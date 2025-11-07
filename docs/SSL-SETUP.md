# SSL/HTTPS Setup Guide

This guide explains how to add SSL/TLS certificate to your NestJS application on AWS ECS.

## Prerequisites

- A domain name (e.g., `yourdomain.com`)
- Access to your domain's DNS settings
- AWS Account with permissions for ACM and Route53

---

## Option 1: AWS Certificate Manager (ACM) - Free & Recommended

### Step 1: Request an SSL Certificate

```bash
# Request a certificate
aws acm request-certificate \
  --domain-name yourdomain.com \
  --subject-alternative-names www.yourdomain.com api.yourdomain.com \
  --validation-method DNS \
  --region us-east-1
```

This returns a Certificate ARN like:
```
arn:aws:acm:us-east-1:123456789012:certificate/abc123...
```

### Step 2: Validate Your Domain

AWS will require you to validate domain ownership:

**Option A: DNS Validation (Recommended)**

1. Get validation records:
```bash
aws acm describe-certificate \
  --certificate-arn arn:aws:acm:us-east-1:123456789012:certificate/abc123... \
  --region us-east-1
```

2. Add the CNAME records shown in the output to your DNS provider

3. Wait for validation (usually 5-30 minutes)

**Option B: Email Validation**

Check the admin email for your domain and click the validation link.

### Step 3: Update Your Deployment

Once validated, deploy with HTTPS:

```bash
# Update the ALB stack with your certificate
aws cloudformation update-stack \
  --stack-name nestjs-prod-alb-stack \
  --template-body file://cloudformation/03-alb.yaml \
  --parameters \
    ParameterKey=EnvironmentName,ParameterValue=nestjs-prod \
    ParameterKey=CertificateArn,ParameterValue=arn:aws:acm:us-east-1:123456789012:certificate/abc123... \
    ParameterKey=RedirectHTTPToHTTPS,ParameterValue=true \
  --region us-east-1
```

### Step 4: Set Up Custom Domain (Optional)

If you have a domain, point it to your load balancer:

**Using Route53:**

```bash
# Get your ALB DNS name
ALB_DNS=$(aws cloudformation describe-stacks \
  --stack-name nestjs-prod-alb-stack \
  --query "Stacks[0].Outputs[?OutputKey=='LoadBalancerUrl'].OutputValue" \
  --output text)

# Create hosted zone (if you don't have one)
aws route53 create-hosted-zone \
  --name yourdomain.com \
  --caller-reference $(date +%s)

# Get hosted zone ID
ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name yourdomain.com \
  --query "HostedZones[0].Id" \
  --output text | cut -d'/' -f3)

# Create A record for your domain
aws route53 change-resource-record-sets \
  --hosted-zone-id $ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "CREATE",
      "ResourceRecordSet": {
        "Name": "yourdomain.com",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z35SXDOTRQ7X7K",
          "DNSName": "'$ALB_DNS'",
          "EvaluateTargetHealth": false
        }
      }
    }]
  }'
```

**Using External DNS Provider:**

Add an A record or CNAME:
- **A Record**: Point to ALB IP (not recommended, IPs can change)
- **CNAME**: Point `api.yourdomain.com` to your ALB DNS name

---

## Option 2: Import Your Own Certificate

If you already have an SSL certificate:

```bash
aws acm import-certificate \
  --certificate fileb://certificate.crt \
  --private-key fileb://private-key.pem \
  --certificate-chain fileb://certificate-chain.crt \
  --region us-east-1
```

Then follow **Step 3** above with the returned ARN.

---

## Option 3: Let's Encrypt (Self-Managed)

For self-managed certificates:

1. Generate certificate using Certbot
2. Import to ACM (see Option 2)
3. Set up auto-renewal using Lambda

⚠️ **Not Recommended**: ACM provides free auto-renewing certificates.

---

## Update CORS for HTTPS

After enabling HTTPS, update your CORS settings:

### Local Development (.env)
```env
CORS_ORIGIN=http://localhost:3000,http://localhost:3001,http://localhost:4200
```

### Production (AWS Secrets Manager)
```bash
aws secretsmanager update-secret \
  --secret-id nestjs-prod/app-secrets \
  --secret-string '{
    "MONGODB_URI": "mongodb://production-host:27017/nestjs-app",
    "MONGODB_DATABASE": "nestjs-app",
    "MONGODB_USER": "prod-admin",
    "MONGODB_PASSWORD": "super-secure-password",
    "CORS_ORIGIN": "https://yourdomain.com,https://www.yourdomain.com",
    "CORS_CREDENTIALS": "true",
    "JWT_SECRET": "your-production-jwt-secret",
    "JWT_EXPIRATION": "7d"
  }' \
  --region us-east-1
```

Then redeploy your ECS service to pick up the new CORS settings.

---

## Testing HTTPS

After deployment:

```bash
# Test HTTPS endpoint
curl -I https://yourdomain.com/health

# Test HTTP redirect (if enabled)
curl -I http://yourdomain.com/health
# Should return 301 redirect to HTTPS

# Test API
curl https://yourdomain.com/users
```

---

## Security Best Practices

1. **Always use TLS 1.2+**: Already configured in the template
   ```yaml
   SslPolicy: ELBSecurityPolicy-TLS13-1-2-2021-06
   ```

2. **Enable HTTP to HTTPS redirect**: Set `RedirectHTTPToHTTPS=true`

3. **Use HSTS Header**: Add to your NestJS app:
   ```typescript
   // src/main.ts
   app.use((req, res, next) => {
     res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
     next();
   });
   ```

4. **Update cookies to secure**:
   ```typescript
   res.cookie('name', 'value', {
     secure: true,
     httpOnly: true,
     sameSite: 'strict'
   });
   ```

---

## Troubleshooting

### Certificate Validation Stuck

- Check DNS records are correct
- Wait up to 72 hours for DNS propagation
- Use `dig` to verify CNAME records:
  ```bash
  dig _abc123.yourdomain.com CNAME
  ```

### 502 Bad Gateway After HTTPS

- Ensure target group health checks pass
- Verify ECS tasks are running
- Check security groups allow ALB → ECS traffic

### Mixed Content Warnings

- Ensure all API calls use HTTPS
- Update environment variables to use `https://`

---

## Cost

**AWS Certificate Manager**: **FREE** ✅
- No charge for SSL certificates
- Automatic renewal
- Unlimited certificates

**Route53** (if used):
- $0.50/month per hosted zone
- $0.40 per million queries

---

## Quick Deploy with HTTPS

```bash
# 1. Request certificate (do this once)
CERT_ARN=$(aws acm request-certificate \
  --domain-name yourdomain.com \
  --subject-alternative-names www.yourdomain.com \
  --validation-method DNS \
  --region us-east-1 \
  --query CertificateArn \
  --output text)

# 2. Validate domain (add DNS records from ACM console)

# 3. Deploy with HTTPS
./scripts/deploy-infrastructure.sh

# When prompted for ALB stack, use:
aws cloudformation update-stack \
  --stack-name nestjs-prod-alb-stack \
  --template-body file://cloudformation/03-alb.yaml \
  --parameters \
    ParameterKey=EnvironmentName,ParameterValue=nestjs-prod \
    ParameterKey=CertificateArn,ParameterValue=$CERT_ARN \
    ParameterKey=RedirectHTTPToHTTPS,ParameterValue=true
```

---

## Summary

✅ **Recommended Setup:**
1. Use AWS Certificate Manager (free)
2. Use DNS validation
3. Enable HTTP → HTTPS redirect
4. Point your domain to ALB via Route53 or CNAME

This provides enterprise-grade SSL/TLS with automatic renewal at no cost! 🎉
