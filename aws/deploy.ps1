# Voting App - AWS EKS Full Deployment Script
# Run from the repo root: .\aws\deploy.ps1
#
# BEFORE RUNNING -- update the variables below to match your environment:
#   $ACCOUNT_ID   -- your 12-digit AWS account ID
#   $SNS_EMAIL    -- email address for deployment notifications
#   $GITHUB_REPO_URL -- your forked repo URL (if you have customised the app)
#
# NOTE: This script contains no credentials or secrets.
# AWS access is provided by the credentials in your current AWS CLI session.

$ErrorActionPreference = "Stop"

$REGION = "ap-southeast-2"
$ACCOUNT_ID = "YOUR_AWS_ACCOUNT_ID"          # <-- replace with your account ID
$CLUSTER_NAME = "voting-app-cluster"
$ECR_BASE = "$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com"
$SNS_EMAIL = "YOUR_EMAIL@example.com"         # <-- replace with your email
$CODEBUILD_PROJECT = "voting-app-build"
$ROLE_CODEBUILD = "VotingAppCodeBuildRole"
$ROLE_EKS_NODE = "VotingAppEKSNodeRole"
# Update this to your forked repo URL if you've customised the app
$GITHUB_REPO_URL = "https://github.com/dockersamples/example-voting-app.git"

function Log($msg) { Write-Host "$(Get-Date -Format 'HH:mm:ss') $msg" -ForegroundColor Cyan }
function OK($msg) { Write-Host "  OK -- $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "  WARN -- $msg" -ForegroundColor Yellow }

Log "================================================"
Log " VOTING APP -- AWS EKS Deployment"
Log "================================================"
Log " Account : $ACCOUNT_ID"
Log " Region  : $REGION"
Log " Cluster : $CLUSTER_NAME"
Log "================================================"

# ── STEP 1: SNS Topic ──────────────────────────────
Log "[1/8] Creating SNS notification topic..."
$SNS_ARN = (aws sns create-topic --name "VotingApp-Notifications" --region $REGION --query "TopicArn" --output text)
aws sns subscribe --topic-arn $SNS_ARN --protocol email --notification-endpoint $SNS_EMAIL --region $REGION | Out-Null
OK "SNS: $SNS_ARN"
OK "Subscription pending -- check $SNS_EMAIL"

# ── STEP 2: ECR Repositories ──────────────────────
Log "[2/8] Creating ECR repositories..."
foreach ($repo in @("voting-app/vote","voting-app/result","voting-app/worker")) {
    $exists = aws ecr describe-repositories --repository-names $repo --region $REGION 2>&1
    if ($LASTEXITCODE -ne 0) {
        aws ecr create-repository --repository-name $repo --region $REGION `
            --image-scanning-configuration scanOnPush=true `
            --encryption-configuration encryptionType=AES256 | Out-Null
        # Lifecycle policy -- keep last 10 images
        $lifecycle = '{"rules":[{"rulePriority":1,"description":"Keep last 10 images","selection":{"tagStatus":"any","countType":"imageCountMoreThan","countNumber":10},"action":{"type":"expire"}}]}'
        aws ecr put-lifecycle-policy --repository-name $repo --lifecycle-policy-text $lifecycle --region $REGION | Out-Null
        OK "Created ECR: $repo"
    } else {
        OK "ECR already exists: $repo"
    }
}

# ── STEP 3: IAM Roles ─────────────────────────────
Log "[3/8] Creating IAM roles..."

# CodeBuild trust policy
$cbTrust = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"codebuild.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

$cbExists = aws iam get-role --role-name $ROLE_CODEBUILD 2>&1
if ($LASTEXITCODE -ne 0) {
    aws iam create-role --role-name $ROLE_CODEBUILD `
        --assume-role-policy-document $cbTrust `
        --description "CodeBuild role for Voting App -- ECR push and EKS deploy" | Out-Null

    $cbPolicy = "{`"Version`":`"2012-10-17`",`"Statement`":[{`"Effect`":`"Allow`",`"Action`":[`"ecr:GetAuthorizationToken`",`"ecr:BatchCheckLayerAvailability`",`"ecr:GetDownloadUrlForLayer`",`"ecr:BatchGetImage`",`"ecr:PutImage`",`"ecr:InitiateLayerUpload`",`"ecr:UploadLayerPart`",`"ecr:CompleteLayerUpload`"],`"Resource`":`"*`"},{`"Effect`":`"Allow`",`"Action`":[`"eks:DescribeCluster`",`"eks:ListClusters`",`"eks:AccessKubernetesApi`"],`"Resource`":`"*`"},{`"Effect`":`"Allow`",`"Action`":[`"logs:CreateLogGroup`",`"logs:CreateLogStream`",`"logs:PutLogEvents`"],`"Resource`":`"*`"},{`"Effect`":`"Allow`",`"Action`":[`"sns:Publish`"],`"Resource`":`"$SNS_ARN`"},{`"Effect`":`"Allow`",`"Action`":[`"s3:GetObject`",`"s3:PutObject`",`"s3:GetBucketAcl`",`"s3:GetBucketLocation`"],`"Resource`":`"*`"}]}"

    aws iam put-role-policy --role-name $ROLE_CODEBUILD `
        --policy-name "VotingAppCodeBuildPolicy" `
        --policy-document $cbPolicy | Out-Null
    OK "CodeBuild role created: $ROLE_CODEBUILD"
} else {
    OK "CodeBuild role already exists"
}

# EKS Node trust policy
$eksTrust = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

$eksExists = aws iam get-role --role-name $ROLE_EKS_NODE 2>&1
if ($LASTEXITCODE -ne 0) {
    aws iam create-role --role-name $ROLE_EKS_NODE `
        --assume-role-policy-document $eksTrust `
        --description "EKS Node role for Voting App" | Out-Null
    aws iam attach-role-policy --role-name $ROLE_EKS_NODE --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy | Out-Null
    aws iam attach-role-policy --role-name $ROLE_EKS_NODE --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly | Out-Null
    aws iam attach-role-policy --role-name $ROLE_EKS_NODE --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy | Out-Null
    aws iam attach-role-policy --role-name $ROLE_EKS_NODE --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy | Out-Null
    OK "EKS node role created: $ROLE_EKS_NODE"
} else {
    OK "EKS node role already exists"
}

# ── STEP 4: EKS Cluster ───────────────────────────
Log "[4/8] Creating EKS cluster (this takes 15-20 minutes)..."
$clusterExists = aws eks describe-cluster --name $CLUSTER_NAME --region $REGION 2>&1
if ($LASTEXITCODE -ne 0) {
    # EKS control-plane role -- uses the existing AccountFullAccessRole
    # Ensure this role has a trust policy allowing eks.amazonaws.com to assume it
    $EKS_CONTROL_PLANE_ROLE = "arn:aws:iam::${ACCOUNT_ID}:role/AccountFullAccessRole"

    $SUBNET_IDS_CLUSTER = (aws ec2 describe-subnets `
        --filters "Name=default-for-az,Values=true" `
        --region $REGION `
        --query "Subnets[*].SubnetId" `
        --output text) -replace '\s+', ','

    aws eks create-cluster `
        --name $CLUSTER_NAME `
        --region $REGION `
        --kubernetes-version "1.31" `
        --role-arn $EKS_CONTROL_PLANE_ROLE `
        --resources-vpc-config "subnetIds=${SUBNET_IDS_CLUSTER},endpointPublicAccess=true,endpointPrivateAccess=false" `
        --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}' | Out-Null
    Log "  Waiting for cluster to become ACTIVE..."
    aws eks wait cluster-active --name $CLUSTER_NAME --region $REGION
    OK "EKS cluster active!"
} else {
    OK "EKS cluster already exists"
}

# ── STEP 5: Node Group ────────────────────────────
Log "[5/8] Creating managed node group..."
$nodeGroupExists = aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name "voting-app-nodes" --region $REGION 2>&1
if ($LASTEXITCODE -ne 0) {
    $NODE_ROLE_ARN = (aws iam get-role --role-name $ROLE_EKS_NODE --query "Role.Arn" --output text)
    $SUBNET_IDS = (aws ec2 describe-subnets --filters "Name=default-for-az,Values=true" --region $REGION --query "Subnets[*].SubnetId" --output text) -replace '\s+',','

    aws eks create-nodegroup `
        --cluster-name $CLUSTER_NAME `
        --nodegroup-name "voting-app-nodes" `
        --region $REGION `
        --node-role $NODE_ROLE_ARN `
        --subnets ($SUBNET_IDS -split ',') `
        --instance-types "t3.medium" `
        --scaling-config "minSize=2,maxSize=4,desiredSize=2" `
        --disk-size 20 `
        --ami-type AL2_x86_64 | Out-Null

    Log "  Waiting for node group to become ACTIVE (5-10 min)..."
    aws eks wait nodegroup-active --cluster-name $CLUSTER_NAME --nodegroup-name "voting-app-nodes" --region $REGION
    OK "Node group active!"
} else {
    OK "Node group already exists"
}

# ── STEP 6: CloudWatch Container Insights ────────
Log "[6/9] Enabling CloudWatch Container Insights on EKS..."
# Ensure the node role has CloudWatch permissions (already attached above)
# Enable via EKS managed addon (amazon-cloudwatch-observability)
$cwAddon = aws eks describe-addon --cluster-name $CLUSTER_NAME --addon-name amazon-cloudwatch-observability --region $REGION 2>&1
if ($LASTEXITCODE -ne 0) {
    aws eks create-addon `
        --cluster-name $CLUSTER_NAME `
        --addon-name amazon-cloudwatch-observability `
        --region $REGION | Out-Null
    OK "CloudWatch Container Insights addon created"
} else {
    OK "CloudWatch Container Insights addon already exists"
}

# ── STEP 7: ALB Controller IAM Policy and Role ───
Log "[7/9] Creating ALB Controller IAM policy and role..."
$LBC_POLICY_NAME = "AWSLoadBalancerControllerIAMPolicy"
$LBC_ROLE_NAME = "AmazonEKSLoadBalancerControllerRole"

$policyExists = aws iam get-policy --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/$LBC_POLICY_NAME" 2>&1
if ($LASTEXITCODE -ne 0) {
    $policyDoc = (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.8.1/docs/install/iam_policy.json" -UseBasicParsing).Content
    $policyDoc | Out-File -FilePath "$env:TEMP\lbc-policy.json" -Encoding utf8
    aws iam create-policy `
        --policy-name $LBC_POLICY_NAME `
        --policy-document "file://$env:TEMP\lbc-policy.json" `
        --region $REGION | Out-Null
    OK "LBC IAM policy created"
} else {
    OK "LBC IAM policy already exists"
}

# OIDC provider (needed for IRSA)
$OIDC_URL = (aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.identity.oidc.issuer" --output text)
$OIDC_ID = $OIDC_URL -replace "https://", "" -replace ".*/", ""
$oidcExists = aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?ends_with(Arn,'$OIDC_ID')].Arn" --output text
if (-not $oidcExists) {
    # eksctl must be available or use AWS CLI equivalent
    # eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --region $REGION --approve
    # Alternatively the buildspec handles this -- flag for manual step
    Warn "OIDC provider not yet associated -- the buildspec will handle this on first build."
    Warn "Or run: eksctl utils associate-iam-oidc-provider --cluster $CLUSTER_NAME --region $REGION --approve"
} else {
    OK "OIDC provider already associated: $oidcExists"
}

$lbcRoleExists = aws iam get-role --role-name $LBC_ROLE_NAME 2>&1
if ($LASTEXITCODE -ne 0) {
    $OIDC_PROVIDER = ($OIDC_URL -replace "https://", "")
    $lbcTrust = "{`"Version`":`"2012-10-17`",`"Statement`":[{`"Effect`":`"Allow`",`"Principal`":{`"Federated`":`"arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}`"},`"Action`":`"sts:AssumeRoleWithWebIdentity`",`"Condition`":{`"StringEquals`":{`"${OIDC_PROVIDER}:aud`":`"sts.amazonaws.com`",`"${OIDC_PROVIDER}:sub`":`"system:serviceaccount:kube-system:aws-load-balancer-controller`"}}}]}"
    aws iam create-role `
        --role-name $LBC_ROLE_NAME `
        --assume-role-policy-document $lbcTrust `
        --description "IRSA role for AWS Load Balancer Controller" | Out-Null
    aws iam attach-role-policy `
        --role-name $LBC_ROLE_NAME `
        --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/$LBC_POLICY_NAME" | Out-Null
    OK "LBC IAM role created: $LBC_ROLE_NAME"
} else {
    OK "LBC IAM role already exists"
}

# ── STEP 8: CodeBuild Artifacts S3 Bucket ────────
Log "[8/9] Creating CodeBuild artifacts bucket..."
$ARTIFACTS_BUCKET = "voting-app-artifacts-$ACCOUNT_ID"
$bucketExists = aws s3api head-bucket --bucket $ARTIFACTS_BUCKET --region $REGION 2>&1
if ($LASTEXITCODE -ne 0) {
    aws s3api create-bucket --bucket $ARTIFACTS_BUCKET --region $REGION `
        --create-bucket-configuration LocationConstraint=$REGION | Out-Null
    OK "S3 artifacts bucket created: $ARTIFACTS_BUCKET"
} else {
    OK "S3 bucket already exists"
}

# ── STEP 9: CodeBuild Project ─────────────────────
Log "[9/9] Creating CodeBuild project..."
$CB_ROLE_ARN = (aws iam get-role --role-name $ROLE_CODEBUILD --query "Role.Arn" --output text)

$projectExists = aws codebuild batch-get-projects --names $CODEBUILD_PROJECT --region $REGION --query "projects[0].name" --output text 2>&1
if ($projectExists -ne $CODEBUILD_PROJECT) {
    $projectJson = @"
{
  "name": "$CODEBUILD_PROJECT",
  "description": "Build and deploy Voting App to EKS",
  "source": {
    "type": "GITHUB",
    "location": "$GITHUB_REPO_URL",
    "buildspec": "aws/buildspec.yml",
    "gitCloneDepth": 1
  },
  "artifacts": {
    "type": "NO_ARTIFACTS"
  },
  "environment": {
    "type": "LINUX_CONTAINER",
    "image": "aws/codebuild/standard:7.0",
    "computeType": "BUILD_GENERAL1_MEDIUM",
    "privilegedMode": true,
    "environmentVariables": [
      {"name": "AWS_REGION", "value": "$REGION"},
      {"name": "ACCOUNT_ID", "value": "$ACCOUNT_ID"},
      {"name": "CLUSTER_NAME", "value": "$CLUSTER_NAME"},
      {"name": "ECR_BASE", "value": "$ECR_BASE"},
      {"name": "SNS_ARN", "value": "$SNS_ARN"}
    ]
  },
  "serviceRole": "$CB_ROLE_ARN",
  "logsConfig": {
    "cloudWatchLogs": {
      "status": "ENABLED",
      "groupName": "/aws/codebuild/voting-app-build"
    }
  }
}
"@
    $projectJson | Out-File -FilePath "$env:TEMP\cb-project.json" -Encoding utf8
    aws codebuild create-project --cli-input-json "file://$env:TEMP\cb-project.json" --region $REGION | Out-Null
    OK "CodeBuild project created: $CODEBUILD_PROJECT"
} else {
    OK "CodeBuild project already exists"
}

# ── Trigger Build ─────────────────────────────────
Log "[Build] Triggering first build..."
$BUILD_ID = (aws codebuild start-build --project-name $CODEBUILD_PROJECT --region $REGION --query "build.id" --output text)
OK "Build started: $BUILD_ID"

# Summary
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host " DEPLOYMENT INITIATED!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host " EKS Cluster  : $CLUSTER_NAME" -ForegroundColor White
Write-Host " CodeBuild    : $CODEBUILD_PROJECT" -ForegroundColor White
Write-Host " Build ID     : $BUILD_ID" -ForegroundColor White
Write-Host " ECR Base     : $ECR_BASE" -ForegroundColor White
Write-Host " SNS Alerts   : $SNS_EMAIL" -ForegroundColor White
Write-Host ""
Write-Host " Monitor build:" -ForegroundColor Yellow
Write-Host " https://$REGION.console.aws.amazon.com/codesuite/codebuild/projects/$CODEBUILD_PROJECT/history" -ForegroundColor Yellow
Write-Host ""
Write-Host " NOTE: Build takes ~10 min. Vote and Result URLs" -ForegroundColor Magenta
Write-Host " will be printed in the build logs when ready." -ForegroundColor Magenta
Write-Host " Check $SNS_EMAIL for deployment notification." -ForegroundColor Magenta