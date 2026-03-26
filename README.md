# Threat Detection & Auto-Remediation Pipeline

An automated AWS security pipeline that detects threats via Amazon GuardDuty, remediates compromised IAM identities in real time using AWS Lambda, sends structured alerts via Amazon SNS, and aggregates findings in AWS Security Hub — all provisioned and managed through Terraform.

## Architecture

```
GuardDuty ──▶ EventBridge ──▶ Lambda (Python 3.12) ──▶ IAM Remediation
                                       │
                                       ├──▶ SNS (Email Alert)
                                       └──▶ CloudWatch Logs

GuardDuty ──▶ Security Hub (automatic integration)
```

**Services used:**

| Service | Purpose |
|---|---|
| Amazon GuardDuty | Continuous threat detection |
| Amazon EventBridge | Routes specific finding types to Lambda |
| AWS Lambda | Executes automated IAM remediation |
| Amazon SNS | Sends structured JSON alerts via email |
| Amazon CloudWatch | Stores Lambda execution logs |
| AWS Security Hub | Aggregates findings for compliance visibility |
| AWS IAM | Least-privilege execution role for Lambda |

**GuardDuty finding types monitored:**

- `UnauthorizedAccess:IAMUser/ConsoleLoginSuccess.NoMFA`
- `UnauthorizedAccess:IAMUser/MaliciousIPCaller.Custom`
- `Recon:IAMUser/MaliciousIPCaller`
- `CredentialAccess:IAMUser/AnomalousBehavior`

## Remediation Logic

When a matching finding is detected, the Lambda function:

1. **Deactivates all access keys** for the compromised IAM user
2. **Deletes the login profile** (console password) for `IAMUser` principals
3. **Logs a skip** for `AssumedRole` principals (roles cannot be disabled directly)
4. **Publishes a structured JSON alert** to SNS with full remediation details
5. **Reports `SUCCESS` or `PARTIAL_FAILURE`** based on action outcomes

## Project Structure

```
threat-detection-pipeline/
├── main.tf                  # Root module composition
├── variables.tf             # Root-level input variables
├── outputs.tf               # Root-level outputs
├── terraform.tfvars         # Variable values (user-specific)
├── modules/
│   ├── guardduty/           # GuardDuty detector
│   ├── eventbridge/         # EventBridge rule, target, Lambda permission
│   ├── lambda/              # Lambda function, IAM role, deployment package
│   ├── notifications/       # SNS topic, email subscription, CloudWatch log group
│   └── security_hub/        # Security Hub account enablement
└── lambda_src/
    └── remediate.py         # Python remediation handler
```

## Prerequisites

- [Terraform](https://www.terraform.io/downloads) >= 1.0
- AWS CLI configured with valid credentials (`aws configure`)
- An AWS account with permissions to create IAM roles, Lambda functions, GuardDuty, SNS, EventBridge, CloudWatch, and Security Hub resources
- A valid email address for SNS alert delivery

## Deployment

1. **Clone the repository:**
   ```bash
   git clone https://github.com/DavidDanso/threat-detection-pipeline.git
   cd threat-detection-pipeline
   ```

2. **Configure variables** — edit `terraform.tfvars`:
   ```hcl
   aws_region   = "us-east-1"
   alert_email  = "your-email@example.com"
   project_name = "threat-pipeline"
   ```

3. **Initialize Terraform:**
   ```bash
   terraform init
   ```

4. **Review the execution plan:**
   ```bash
   terraform plan
   ```

5. **Deploy the infrastructure:**
   ```bash
   terraform apply
   ```

6. **Confirm the SNS email subscription** — check your inbox and click the AWS confirmation link. Alerts will not be delivered until this is done.

## Testing

### Full End-to-End Test (Recommended)

This test validates the complete remediation path against a real IAM identity — access key deactivation, login profile deletion, SNS alert delivery, and CloudWatch logging.

**1. Get your AWS account ID:**
```bash
aws sts get-caller-identity --query Account --output text
```

**2. Create a throwaway test user with a real access key and login profile:**
```bash
aws iam create-user --user-name compromised-test-user
aws iam create-access-key --user-name compromised-test-user
aws iam create-login-profile --user-name compromised-test-user --password 'TempPass123!@#' --password-reset-required
```

Save the `AccessKeyId` returned from the second command.

**3. Invoke the Lambda directly with a crafted payload:**

> **Note:** `--cli-binary-format raw-in-base64-out` is required for AWS CLI v2. Omit this flag if you are on CLI v1.

```bash
aws lambda invoke \
  --function-name $(terraform output -raw lambda_function_name) \
  --payload '{"version":"0","id":"test-001","detail-type":"GuardDuty Finding","source":"aws.guardduty","detail":{"schemaVersion":"2.0","accountId":"<your_account_id>","region":"<your_region>","type":"CredentialAccess:IAMUser/AnomalousBehavior","severity":8,"createdAt":"2026-01-01T00:00:00Z","id":"test-finding-001","resource":{"resourceType":"AccessKey","accessKeyDetails":{"userType":"IAMUser","userName":"compromised-test-user","accessKeyId":"<AccessKeyId>","userAccount":"<your_account_id>"}}}}' \
  --cli-binary-format raw-in-base64-out \
  response.json && cat response.json
```

Replace `<your_account_id>`, `<your_region>`, and `<AccessKeyId>` with real values.

Expected response:
```json
{"statusCode": 200, "body": "Remediation complete. Status: SUCCESS"}
```

If you see `PARTIAL_FAILURE`, one IAM action did not complete. Check CloudWatch Logs (Step 4) for the specific error before proceeding.

**4. Check CloudWatch Logs for execution details:**
```bash
# Get the latest log stream name
aws logs describe-log-streams \
  --log-group-name /aws/lambda/$(terraform output -raw lambda_function_name) \
  --order-by LastEventTime \
  --descending \
  --limit 1 \
  --query 'logStreams[0].logStreamName' \
  --output text
```

Then pull the log events — replace `<log_stream_name>` with the output from the command above:
```bash
aws logs get-log-events \
  --log-group-name /aws/lambda/$(terraform output -raw lambda_function_name) \
  --log-stream-name '<log_stream_name>'
```

Confirm the logs show: finding received → access key deactivated → login profile deleted → SNS alert published.

**5. Verify the remediation happened in AWS:**
```bash
# Access key must show Status: Inactive
aws iam list-access-keys --user-name compromised-test-user

# Login profile must return NoSuchEntity (Lambda deleted it)
aws iam get-login-profile --user-name compromised-test-user
```

**6. Check your email inbox** — confirm the structured JSON alert arrived with `remediation_status: SUCCESS` and `affected_principal.username: compromised-test-user`.

**7. Clean up the test user:**

Run these commands in this exact order. Skipping or reordering will cause `DeleteConflict` errors.

```bash
# Step 1 — delete the access key (Lambda deactivated it but did not delete it)
aws iam delete-access-key --user-name compromised-test-user --access-key-id <AccessKeyId>

# Step 2 — delete the login profile if it still exists
# If Lambda successfully deleted it, this returns NoSuchEntityException — that is expected and can be ignored
aws iam delete-login-profile --user-name compromised-test-user

# Step 3 — delete the user
aws iam delete-user --user-name compromised-test-user
```

---

### EventBridge Routing Verification

This test confirms EventBridge is correctly wired to Lambda. It uses a fabricated GuardDuty identity so IAM remediation will fail with `PARTIAL_FAILURE` — that is expected. The only thing being verified here is that EventBridge routes the finding to Lambda.

```bash
aws guardduty create-sample-findings \
  --detector-id $(terraform output -raw guardduty_detector_id) \
  --finding-types 'CredentialAccess:IAMUser/AnomalousBehavior'
```

Wait 2 minutes, then check CloudWatch Logs for a second Lambda invocation log stream.

---

### Final Verification Checklist

After running both tests confirm:

- `response.json` returned `statusCode: 200` and `Status: SUCCESS`
- CloudWatch Logs show access key deactivated and login profile deleted
- SNS email delivered to inbox with correct structured JSON body
- A second Lambda invocation in CloudWatch Logs confirms EventBridge routing
- Security Hub CSPM → Findings shows GuardDuty findings visible

## Troubleshooting

**Lambda not triggered by EventBridge**
- Confirm the EventBridge rule is enabled: `aws events describe-rule --name <rule_name>`
- Confirm `aws_lambda_permission` exists for `events.amazonaws.com` — without it EventBridge cannot invoke Lambda even if the target is set correctly

**SNS email not delivered**
- The SNS subscription must be confirmed before emails arrive. Check the subscription status:
  ```bash
  aws sns list-subscriptions-by-topic --topic-arn $(terraform output -raw sns_topic_arn)
  ```
- If status is `PendingConfirmation`, check your inbox for the AWS confirmation email and click the link

**Lambda returns `PARTIAL_FAILURE`**
- Check CloudWatch Logs for the specific IAM action that failed
- Confirm the Lambda IAM execution role has `iam:ListAccessKeys`, `iam:UpdateAccessKey`, `iam:DeleteLoginProfile`, and `iam:GetUser` scoped to `arn:aws:iam::*:user/*`

**Security Hub shows no findings**
- Confirm GuardDuty and Security Hub are both enabled in the same region
- Check the GuardDuty integration is active:
  ```bash
  aws securityhub list-enabled-products-for-import
  ```
- If GuardDuty is not listed, enable the integration:
  ```bash
  aws securityhub enable-import-findings-from-product \
    --product-arn "arn:aws:securityhub:<your_region>::product/aws/guardduty"
  ```

**`terraform apply` fails on Security Hub**
- Security Hub must be applied after GuardDuty. Confirm `depends_on = [module.guardduty]` exists on the `module "security_hub"` block in root `main.tf`

## Cost Note

- **GuardDuty** offers a 30-day free trial. After the trial, finding analysis is billed per GB of data volume analyzed.
- **Lambda**, **SNS**, **CloudWatch**, and **EventBridge** costs are minimal for this use case and typically fall within the AWS Free Tier.
- **Security Hub** has a 30-day free trial. After that, pricing is based on the number of security checks and finding ingestion events.

## Teardown

> **⚠️ Warning:** Running `terraform destroy` will disable GuardDuty and Security Hub. In a real production account, this is a **security regression** — you will lose continuous threat monitoring. Only destroy in development or sandbox environments.

```bash
terraform destroy
```

## Outputs

| Output | Description |
|---|---|
| `guardduty_detector_id` | GuardDuty detector ID |
| `sns_topic_arn` | SNS topic ARN for alerts |
| `lambda_function_arn` | Lambda function ARN |
| `lambda_function_name` | Lambda function name |
| `event_rule_arn` | EventBridge rule ARN |