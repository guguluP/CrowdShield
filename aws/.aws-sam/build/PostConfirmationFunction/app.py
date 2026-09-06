"""
CrowdShield — Cognito PostConfirmation trigger.

Fires automatically after a user confirms their email via self-signup
(SignUp + ConfirmSignUp). Adds them to the "Public" Cognito group so the
app's role-derivation logic (UserSession.apply, based on the ID token's
cognito:groups claim) grants them public access by default.

Deliberately does NOT touch the "Command" group under any circumstance —
Command access stays a manual step (AWS console or admin API), never
something a self-signup flow can grant itself. This is the actual security
boundary: even a malicious client can't get Command by calling SignUp.

Cognito requires this trigger to return the event unchanged (mutated only if
adding custom attributes, which we don't). If group assignment fails for any
reason, we log and still return the event so the user's signup isn't blocked
by a group-assignment hiccup — they'd just default to no group, which the
app treats as least-privilege (no operational access) rather than an error.
"""

from __future__ import annotations

import os

import boto3
from botocore.exceptions import ClientError

cognito = boto3.client("cognito-idp")

PUBLIC_GROUP_NAME = "Public"


def handler(event, context):
    # Only act on the actual confirmation trigger source, not the other
    # PostConfirmation sub-triggers Cognito can invoke this same Lambda for
    # (e.g. PostConfirmation_ConfirmForgotPassword shouldn't re-add a group).
    trigger_source = event.get("triggerSource", "")
    if trigger_source != "PostConfirmation_ConfirmSignUp":
        return event

    user_pool_id = event.get("userPoolId") or os.environ.get("USER_POOL_ID")
    username = event.get("userName")

    if not user_pool_id or not username:
        # Nothing sane to do — return unchanged rather than fail the signup.
        return event

    try:
        cognito.admin_add_user_to_group(
            UserPoolId=user_pool_id,
            Username=username,
            GroupName=PUBLIC_GROUP_NAME,
        )
    except ClientError as exc:
        # Log for visibility in CloudWatch; never raise, since raising here
        # would surface as a failed signup to the user even though their
        # account was actually created successfully.
        print(f"PostConfirmation: failed to add {username} to {PUBLIC_GROUP_NAME}: {exc}")

    return event
