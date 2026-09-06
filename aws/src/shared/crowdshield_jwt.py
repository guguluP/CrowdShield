"""
CrowdShield — Cognito JWT verification for WebSocket Lambdas.

API Gateway WebSocket APIs (unlike HTTP APIs) have no built-in JWT
authorizer, so $connect must verify the token itself. This fetches Cognito's
public JWKS once per cold start (cached at module scope) and verifies the
token's signature, issuer, and expiry using python-jose.

Deliberately minimal: only what $connect needs (verify + extract
cognito:groups and email). Not a general-purpose auth library.
"""

from __future__ import annotations

import json
import os
import urllib.request
from functools import lru_cache

from jose import jwt
from jose.exceptions import JOSEError

USER_POOL_ID = os.environ.get("USER_POOL_ID", "")
USER_POOL_CLIENT_ID = os.environ.get("USER_POOL_CLIENT_ID", "")
AWS_REGION = os.environ.get("AWS_REGION", "ap-south-2")


class TokenInvalid(Exception):
    pass


@lru_cache(maxsize=1)
def _jwks() -> dict:
    """
    Fetches and caches Cognito's public signing keys for this user pool.
    lru_cache keeps this in memory for the lifetime of the Lambda execution
    environment (i.e. across warm invocations), avoiding a network call on
    every single connection.
    """
    url = f"https://cognito-idp.{AWS_REGION}.amazonaws.com/{USER_POOL_ID}/.well-known/jwks.json"
    with urllib.request.urlopen(url, timeout=5) as response:
        return json.loads(response.read())


def verify_id_token(token: str) -> dict:
    """
    Verifies a Cognito ID token's signature, issuer, audience, and expiry.
    Returns the decoded claims dict on success; raises TokenInvalid on any
    failure (bad signature, wrong pool, expired, malformed).
    """
    try:
        unverified_header = jwt.get_unverified_header(token)
    except JOSEError as exc:
        raise TokenInvalid(f"Malformed token header: {exc}") from exc

    kid = unverified_header.get("kid")
    key = next((k for k in _jwks().get("keys", []) if k.get("kid") == kid), None)
    if key is None:
        raise TokenInvalid("Signing key not found in JWKS (unknown kid).")

    issuer = f"https://cognito-idp.{AWS_REGION}.amazonaws.com/{USER_POOL_ID}"

    try:
        claims = jwt.decode(
            token,
            key,
            algorithms=["RS256"],
            audience=USER_POOL_CLIENT_ID,
            issuer=issuer,
        )
    except JOSEError as exc:
        raise TokenInvalid(f"Token verification failed: {exc}") from exc

    return claims


def groups_from_claims(claims: dict) -> list[str]:
    groups = claims.get("cognito:groups", [])
    if isinstance(groups, list):
        return groups
    return []
