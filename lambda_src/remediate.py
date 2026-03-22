import boto3
import json
import os
import logging
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

iam = boto3.client('iam')
sns = boto3.client('sns')

def handler(event, context):
    logger.info("Finding received: %s", json.dumps(event))

    detail = event.get("detail", {})
    resource = detail.get("resource", {})
    access_key_details = resource.get("accessKeyDetails", {})

    finding_type = detail.get("type", "UNKNOWN_TYPE")
    finding_id = detail.get("id", "UNKNOWN_ID")
    
    # Safe fallback for region and accountId
    region = detail.get("region", event.get("region", "UNKNOWN_REGION"))
    account_id = detail.get("accountId", event.get("account", "UNKNOWN_ACCOUNT"))
    
    severity_num = detail.get("severity", 0)
    severity = "LOW"
    try:
        if float(severity_num) >= 7.0:
            severity = "HIGH"
        elif float(severity_num) >= 4.0:
            severity = "MEDIUM"
    except ValueError:
        pass

    user_name = access_key_details.get("userName")
    user_type = access_key_details.get("userType", "UNKNOWN")
    
    # For user details, principalId often contains the ARN or unique identifier
    principal_id_or_arn = access_key_details.get("principalId", "UNKNOWN_ARN")

    remediation_actions = []
    failures = False
    
    logger.info("Remediation started for userType: %s, userName: %s", user_type, user_name)

    if user_name:
        # Step 1: Deactivate access keys
        try:
            keys_res = iam.list_access_keys(UserName=user_name)
            for md in keys_res.get('AccessKeyMetadata', []):
                key_id = md.get('AccessKeyId')
                if key_id:
                    try:
                        iam.update_access_key(UserName=user_name, AccessKeyId=key_id, Status='Inactive')
                        msg = f"Deactivated access key {key_id} for user {user_name}"
                        logger.info(msg)
                        remediation_actions.append(msg)
                    except Exception as e:
                        failures = True
                        logger.error("Failed to deactivate key %s: %s", key_id, str(e))
        except Exception as e:
            failures = True
            logger.error("Failed to list access keys for user %s: %s", user_name, str(e))

        # Step 2: Delete login profile (Only for IAMUser)
        if user_type == "IAMUser":
            try:
                iam.delete_login_profile(UserName=user_name)
                msg = f"Deleted login profile for user {user_name}"
                logger.info(msg)
                remediation_actions.append(msg)
            except ClientError as e:
                # Catch NoSuchEntity safely
                if e.response.get('Error', {}).get('Code') == 'NoSuchEntity':
                    msg = f"No login profile exists for user {user_name}"
                    logger.info(msg)
                    remediation_actions.append(msg)
                else:
                    failures = True
                    logger.error("Failed to delete login profile for user %s: %s", user_name, str(e))
            except Exception as e:
                failures = True
                logger.error("Failed to delete login profile for user %s: %s", user_name, str(e))
        elif user_type == "AssumedRole":
            msg = "Login profile deletion skipped for AssumedRole (roles cannot be disabled directly)."
            logger.info(msg)
            remediation_actions.append(msg)
    else:
        failures = True
        logger.error("No userName found in finding details.")

    # Determine final remediation status
    if failures:
        remediation_status = "PARTIAL_FAILURE"
    else:
        remediation_status = "SUCCESS"

    # Construct structured SNS Message
    sns_message = {
        "alert_type": "THREAT_DETECTED_AND_REMEDIATED",
        "severity": severity,
        "timestamp": event.get("time", "UNKNOWN_TIME"),
        "finding": {
            "type": finding_type,
            "id": finding_id,
            "region": region,
            "account_id": account_id
        },
        "affected_principal": {
            "type": user_type,
            "username": user_name or "UNKNOWN",
            "arn": principal_id_or_arn
        },
        "remediation_actions": remediation_actions,
        "remediation_status": remediation_status,
        "lambda_request_id": getattr(context, 'aws_request_id', 'UNKNOWN_ID') if context else 'UNKNOWN_ID'
    }

    # Publish SNS alert regardless of failure or success
    try:
        topic_arn = os.environ.get("SNS_TOPIC_ARN", "")
        if topic_arn:
            sns.publish(
                TopicArn=topic_arn,
                Message=json.dumps(sns_message, indent=2),
                Subject=f"GuardDuty Remediation Alert: {remediation_status}"
            )
            logger.info(f"SNS alert sent successfully to {topic_arn}.")
        else:
            logger.error("SNS_TOPIC_ARN environment variable not set.")
    except Exception as e:
        logger.error("Failed to send SNS alert: %s", str(e))

    return {
        "statusCode": 200,
        "body": json.dumps({"message": "Remediation logic executed.", "status": remediation_status})
    }
