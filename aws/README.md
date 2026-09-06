# CrowdShield — AWS Phase 1

Free-tier-friendly foundation only:

| Resource | Purpose |
|---|---|
| **Cognito User Pool** + app client | Auth ready for Phase 2 (groups: `Public`, `Command`) |
| **HTTP API** + **Lambda** | `GET /health` → 200 |
| **DynamoDB** (4 tables) | Venue state, alerts, incidents, recommendations |
| **IAM** | Least-privilege role for the health Lambda |

No EC2, NAT, RDS, or SMS — stays inside Always Free for demo traffic.

---

## Prerequisites

1. AWS account ([aws.amazon.com](https://aws.amazon.com/))
2. [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) configured:
   ```bash
   aws configure
   # set region e.g. ap-south-1
   ```
3. [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html)

Optional: create a **Billing → Budgets** alert at $1 so you never get surprised.

---

## Deploy (one-time)

From this `aws/` folder:

```bash
cd CrowdShield/aws

# Build the Lambda package
sam build

# First deploy (guided) — accept defaults or set region ap-south-1
sam deploy --guided
```

On later deploys:

```bash
sam build && sam deploy
```

When the stack finishes, SAM prints **Outputs**. Note:

- `HealthUrl` — open in a browser; you should see JSON with `"status": "ok"`
- `UserPoolId` / `UserPoolClientId` — for iOS (Phase 2)
- `ApiEndpoint` — base URL for later routes

### Quick test

```bash
curl "$(aws cloudformation describe-stacks \
  --stack-name crowdshield-phase1 \
  --query "Stacks[0].Outputs[?OutputKey=='HealthUrl'].OutputValue" \
  --output text)"
```

Expected shape:

```json
{
  "service": "CrowdShield",
  "phase": 1,
  "status": "ok",
  "environment": "dev",
  "checks": { "api": true, "dynamodbVenueState": true }
}
```

---

## What was created

### Cognito
- User pool: `crowdshield-dev-users`
- App client (no secret — suitable for iOS)
- Groups: **Public**, **Command** (not enforced on API yet — Phase 2 JWT)

### DynamoDB (provisioned 5 RCU / 5 WCU each — well under free 25)

| Table | Key |
|---|---|
| `crowdshield-dev-venue-state` | `venueId` |
| `crowdshield-dev-alerts` | `venueId` + `alertId` (+ TTL `expiresAt`) |
| `crowdshield-dev-incidents` | `venueId` + `incidentId` (+ TTL) |
| `crowdshield-dev-recommendations` | `venueId` + `recommendationId` |

### API
- `GET /{stage}/health` — public, no auth

---

## Cost notes (Phase 1)

- Idle stack ≈ **$0** on Always Free (Lambda + Cognito MAU + DynamoDB provisioned free tier).
- Do **not** add NAT Gateway, EC2, or SMS.
- Set CloudWatch log retention on the Lambda log group to **7 days** in the console after first invoke (optional hygiene).

---

## Tear down (when done)

```bash
sam delete --stack-name crowdshield-phase1
```

---

## Next (Phase 2+)

Not included yet (on purpose):

- JWT authorizer on API (Cognito)
- `PUT /venues/{id}/state`, `POST /incidents`, ack recommendations
- iOS Amplify / SDK wiring
- WebSocket live updates
- SNS push

Phase 1 only proves the account, IAM, tables, and a live URL.
