<img width="960" height="620" alt="architecture-overview" src="https://github.com/user-attachments/assets/91d06a9a-f7ba-47ad-844b-8fcf8bda0bf4" />
# 🛡️ CrowdShield

**AI-powered crowd safety and stampede-prevention platform for large public events — an iOS/macOS command app backed by a real-time serverless AWS backend.**

CrowdShield was built against a "TechNova" event-safety brief: predict crowd crushes and stampedes *before* they happen, guide operators to the right intervention, and keep the public informed — all without collecting a single frame of identifiable imagery. It ships two experiences in one app — a **Command & Control** console for safety officers and a **Public** safety companion for attendees — sharing one live venue state over WebSockets.

> Built independently by [@guguluP](https://github.com/guguluP), from SwiftUI client to AWS SAM backend.

---

## Table of Contents

- [Why CrowdShield](#why-crowdshield)
- [Feature Tour](#feature-tour)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
  - [iOS/macOS App](#iosmacos-app)
  - [AWS Backend](#aws-backend)
- [Backend API Reference](#backend-api-reference)
- [The Prediction Engines](#the-prediction-engines)
- [Privacy & Ethics by Design](#privacy--ethics-by-design)
- [Testing](#testing)
- [Cost Model](#cost-model)
- [Roadmap](#roadmap)
- [License](#license)

---

## Why CrowdShield

Crowd crushes rarely happen because nobody was watching — they happen because the *warning signs* (rising density, reversing flow, a bottleneck quietly filling up) are scattered across too many feeds for a human to fuse in time. CrowdShield's core bet is that **stampede risk is predictable several minutes out** if you track density, movement speed, flow direction, and short-term trend together, instead of alerting on a single threshold.

The app is organized around two roles that see the same live venue through very different lenses:

| Role | Who | What they see |
|---|---|---|
| 🧭 **Command & Control** | Safety officers, control-room staff, first responders | Full dashboard: live risk map, stampede/panic predictions, evacuation routing, sensor ingestion, AI incident summaries, multilingual broadcast tools |
| 👤 **Public** | Attendees, general public | Safety heat map, real-time alerts, one-tap incident reporting, safety guidance — zero operational or sensitive data |

Both roles are enforced **server-side** via Cognito group membership in the JWT — not just hidden in the UI.

---

## Feature Tour

### For Command & Control
- **Live command dashboard** — overall venue risk, predicted time-to-crush, active zone count, and critical-zone flagging, updated over a real-time feed.
- **Stampede & panic prediction** — a dedicated engine scores each zone's *stampede likelihood* and models how panic intensity would propagate across the venue's walkable graph, with the primary contributing signals surfaced per zone.
- **Evacuation routing** — computes the nearest-safe-exit path from any zone across a modeled venue graph (gates, plazas, stands, bottlenecks), so a recommendation isn't just "there's a problem here" but "send people this way."
- **Digital Twin** — a live 3D RealityKit scene where each venue zone is a column whose *height and color* both encode real-time risk, projected from the venue's actual geographic layout rather than an arbitrary mockup.
- **AI incident summaries** — one tap generates a natural-language command brief (headline, body, recommended next step) via a Bedrock (Claude) backend endpoint, with a fully offline on-device fallback (Apple Foundation Models, then a deterministic template) so officers are never left without a brief.
- **Multilingual command assistant** — broadcast pre-vetted safety announcements in the crowd's language, or have the current venue status read aloud via speech synthesis.
- **Recommendations workflow** — prioritized, typed action cards (open exit, close gate, redeploy staff, announce, redirect flow, change barricade) that officers acknowledge, with who/when tracked.
- **Multi-venue support** — Command users can create new venues from the venue registry; both roles select from the live registry rather than a single hardcoded event.
- **Sensor ingestion abstraction** — pluggable sensor sources (simulated, on-device Vision-based density estimation, crowd-sourced phone signal) behind one protocol, so moving from demo to real deployment is a source swap, not a rewrite.

### For the Public
- **Live safety map** — real-time density heat map of the venue.
- **Real-time alerts** — pushed the moment Command issues one, translated across six languages.
- **One-tap incident reporting** — location-tagged, with optional anonymity.
- **Privacy & Ethics screen** — the app's privacy commitments rendered as an in-app, user-facing surface (see below) — not just a policy document nobody reads.

### Cross-cutting
- **Real Cognito authentication** — sign up, email confirmation, sign-in, forgot/reset password, and silent session restore via Keychain-backed refresh tokens.
- **Offline-aware** — a network reachability monitor lets the app degrade gracefully during venue network overload rather than fail silently.
- **Alert debouncing** — a two-layer persistence + cooldown system so a single noisy sensor tick can't fire an alert, and a flickering condition can't spam the same alert repeatedly.
- **Liquid Glass UI** — adaptive `.glassEffect` on iOS/macOS 26+, with a graceful `.ultraThinMaterial` fallback on older OS versions, and role-aware accent theming (cyan for Public, amber for Command) throughout.

> **Screenshots:** none are checked into this repo yet. Build and run the `CrowdShield` scheme on a device or Mac (see [Getting Started](#getting-started)) to see the Command dashboard, Digital Twin, and Public map firsthand — happy to add real screenshots here once captured. In the meantime, the [architecture diagrams](#architecture) below cover how the pieces fit together.

---

## Architecture
<svg width="960" height="620" viewBox="0 0 960 620" xmlns="http://www.w3.org/2000/svg" font-family="-apple-system, 'Segoe UI', Helvetica, Arial, sans-serif" role="img" aria-labelledby="title desc" xmlns:c2pa="http://c2pa.org/manifest"><metadata><c2pa:manifest>AAAWgmp1bWIAAAAeanVtZGMycGEAEQAQgAAAqgA4m3EDYzJwYQAAABZcanVtYgAAAEdqdW1kYzJtYQARABCAAACqADibcQN1cm46YzJwYTo4MDBkNjRhYy1lNTc1LTQ2MjktOWM5ZC05NTUwZTNjYTEwMDMAAAADl2p1bWIAAAApanVtZGMyYXMAEQAQgAAAqgA4m3EDYzJwYS5hc3NlcnRpb25zAAAAALxqdW1iAAAARGp1bWRjYm9yABEAEIAAAKoAOJtxE2MycGEuaW5ncmVkaWVudC52MwAAAAAYYzJzaBLrh3Eykg0qLxeuAfsprnwAAABwY2JvcqNpZGM6Zm9ybWF0bWltYWdlL3N2Zyt4bWxqaW5zdGFuY2VJRHgseG1wOmlpZDpjMGU2ZThlZS0wNzBlLTRmZGItYjA4Yy1hZjdiNDM5NjZkNWVscmVsYXRpb25zaGlwaHBhcmVudE9mAAAB4mp1bWIAAABBanVtZGNib3IAEQAQgAAAqgA4m3ETYzJwYS5hY3Rpb25zLnYyAAAAABhjMnNoeHkXOhSJYrKQ5sc/YiLZdQAAAZljYm9yomdhY3Rpb25zgqJmYWN0aW9ua2MycGEub3BlbmVkanBhcmFtZXRlcnOha2luZ3JlZGllbnRzgaJjdXJseC1zZWxmI2p1bWJmPWMycGEuYXNzZXJ0aW9ucy9jMnBhLmluZ3JlZGllbnQudjNkaGFzaFgg1iVLHqATMCl8WznVYpvpxZNakiKYYtUziM0lKxgkrjykZmFjdGlvbngdY29tLmFudGhyb3BpYy5jbGF1ZGUucHJvdmlkZWRqcGFyYW1ldGVyc6F4H2NvbS5hbnRocm9waWMub3JpZ2luLWNvbmZpZGVuY2VndW5rbm93bmtkZXNjcmlwdGlvbnhmQ2xhdWRlIHByb3ZpZGVkIHRoaXMgZmlsZSBhdCB0aGUgcmVxdWVzdCBvZiBhIHVzZXIgYW5kIG1heSBoYXZlIGNyZWF0ZWQgb3IgbW9kaWZpZWQgdGhlIGZpbGUgY29udGVudHMubXNvZnR3YXJlQWdlbnShZG5hbWVmQ2xhdWRlcmFsbEFjdGlvbnNJbmNsdWRlZPUAAADIanVtYgAAAEBqdW1kY2JvcgARABCAAACqADibcRNjMnBhLmhhc2guZGF0YQAAAAAYYzJzaGCzsqE0fiEP7AhYr8MPot4AAACAY2JvcqVjYWxnZnNoYTI1NmNwYWRMAAAAAAAAAAAAAAAAZGhhc2hYIGhNMSpDTSmygUl4W0eQOKSgzvEoCdAjguuizM9cGVmRZG5hbWVuanVtYmYgbWFuaWZlc3RqZXhjbHVzaW9uc4GiZXN0YXJ0GQEEZmxlbmd0aBkeBAAAAj5qdW1iAAAAJ2p1bWRjMmNsABEAEIAAAKoAOJtxA2MycGEuY2xhaW0udjIAAAACD2Nib3KlY2FsZ2ZzaGEyNTZpc2lnbmF0dXJleE1zZWxmI2p1bWJmPS9jMnBhL3VybjpjMnBhOjgwMGQ2NGFjLWU1NzUtNDYyOS05YzlkLTk1NTBlM2NhMTAwMy9jMnBhLnNpZ25hdHVyZWppbnN0YW5jZUlEeCx4bXA6aWlkOjM2MDU4YjdlLWI0MGItNGEzZC05MWE4LWQ4MTJjOTAzYmU5N3JjcmVhdGVkX2Fzc2VydGlvbnODomN1cmx4LXNlbGYjanVtYmY9YzJwYS5hc3NlcnRpb25zL2MycGEuaW5ncmVkaWVudC52M2RoYXNoWCDWJUseoBMwKXxbOdVim+nFk1qSIphi1TOIzSUrGCSuPKJjdXJseCpzZWxmI2p1bWJmPWMycGEuYXNzZXJ0aW9ucy9jMnBhLmFjdGlvbnMudjJkaGFzaFggtJmOtywDumppV0f0dUsY+n/XEXcN6zR7RBDpEeyEq/KiY3VybHgpc2VsZiNqdW1iZj1jMnBhLmFzc2VydGlvbnMvYzJwYS5oYXNoLmRhdGFkaGFzaFggJI5N1XzFAGhFkCQsw+Sr+ZEX+UQrKgEco0bMocf9pgZ0Y2xhaW1fZ2VuZXJhdG9yX2luZm+jZG5hbWVvQW50aHJvcGljIEZpbGVzZ3ZlcnNpb25lMS4wLjBrc3BlY1ZlcnNpb25lMi40LjAAABA4anVtYgAAAChqdW1kYzJjcwARABCAAACqADibcQNjMnBhLnNpZ25hdHVyZQAAABAIY2JvctKEWQISogEmGCFZAgowggIGMIIBjaADAgECAhRA5aAK7sI50L64g/oGQgU9Z1UTADAKBggqhkjOPQQDAzBJMRcwFQYDVQQKEw5BbnRocm9waWMsIFBCQzEuMCwGA1UEAxMlQW50aHJvcGljIENvbnRlbnQgQ3JlZGVudGlhbHMgUm9vdCBDQTAeFw0yNjA4MDcxODQzNTZaFw0yODA4MDYxOTQzNTZaMEQxFzAVBgNVBAoTDkFudGhyb3BpYywgUEJDMSkwJwYDVQQDEyBBbnRocm9waWMgQ2xhdWRlIENvbnRlbnQgU2lnbmluZzBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABJh6CmvLUBgFFNU0vUKlOVtE6djd17L5SuwX0LemFisBM3dkd/3cyjxFA3Qo5S46fX0/ihY0VZ7mfb9KF703t5OjWDBWMA4GA1UdDwEB/wQEAwIHgDAVBgNVHSUEDjAMBgorBgEEAYPoXgIBMAwGA1UdEwEB/wQCMAAwHwYDVR0jBBgwFoAUzlHiBIFOZFsj+OPEz5o+nMHXXMIwCgYIKoZIzj0EAwMDZwAwZAIwMXMdFJ4BetLLVY7ORuE9noqbbAZOZn/aArXyTwFAZfKrPzxF2vPoJNf1+UCdg1XGAjBwX1zd9WGqYkqmL5SFqw1QySjr1zJfpJM9+1rdDwSPLMOPOjKuiXjoU/pUUeG9RwmhY3BhZFkNngAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPZYQHOnYEZnCAkE7MdtrboOTk+6AQCtu5gR82+LoV9qR8dB/7YhDrwSgqaOSUUBwkUDLfW+jjg/2hGE3Tcy+f9K9kw=</c2pa:manifest></metadata>
  <title id="title">CrowdShield system architecture</title>
  <desc id="desc">SwiftUI client with on-device engines connects over HTTPS and WebSocket to an AWS SAM backend consisting of Cognito, an HTTP API, seven Lambda functions, DynamoDB tables, a WebSocket API, Bedrock, and CloudWatch alarms feeding SNS.</desc>

  <defs>
    <marker id="arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
      <path d="M1 1L9 5L1 9" fill="none" stroke="#5b6472" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>
    </marker>
    <marker id="arrowTeal" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
      <path d="M1 1L9 5L1 9" fill="none" stroke="#0f6e56" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>
    </marker>
    <marker id="arrowAmber" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
      <path d="M1 1L9 5L1 9" fill="none" stroke="#854f0b" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>
    </marker>
  </defs>

  <rect width="960" height="620" fill="#ffffff"/>

  <!-- ============ CLIENT CONTAINER ============ -->
  <rect x="30" y="30" width="380" height="560" rx="18" fill="#EEEDFE" stroke="#534AB7" stroke-width="1"/>
  <text x="52" y="60" font-size="15" font-weight="600" fill="#26215C">CrowdShield app (SwiftUI)</text>
  <text x="52" y="79" font-size="12" fill="#3C3489">iOS 26 / macOS 26 &#183; runs fully offline-capable</text>

  <!-- Role UIs -->
  <rect x="52" y="98" width="160" height="54" rx="10" fill="#E1F5EE" stroke="#0f6e56" stroke-width="0.75"/>
  <text x="132" y="120" font-size="13" font-weight="600" text-anchor="middle" fill="#085041">Public UI</text>
  <text x="132" y="137" font-size="11" text-anchor="middle" fill="#0F6E56">Map, alerts, reports</text>

  <rect x="228" y="98" width="160" height="54" rx="10" fill="#FAEEDA" stroke="#854f0b" stroke-width="0.75"/>
  <text x="308" y="120" font-size="13" font-weight="600" text-anchor="middle" fill="#412402">Command UI</text>
  <text x="308" y="137" font-size="11" text-anchor="middle" fill="#854F0B">Dashboard, twin, routing</text>

  <line x1="132" y1="152" x2="240" y2="182" stroke="#7F77DD" stroke-width="1"/>
  <line x1="308" y1="152" x2="240" y2="182" stroke="#7F77DD" stroke-width="1"/>

  <!-- Orchestrator -->
  <rect x="130" y="182" width="220" height="46" rx="10" fill="#CECBF6" stroke="#534AB7" stroke-width="0.75"/>
  <text x="240" y="210" font-size="13" font-weight="600" text-anchor="middle" fill="#26215C">CrowdSimulationService</text>

  <line x1="240" y1="228" x2="240" y2="250" stroke="#7F77DD" stroke-width="1"/>

  <!-- On-device engines -->
  <rect x="52" y="250" width="336" height="140" rx="12" fill="#ffffff" stroke="#AFA9EC" stroke-width="0.75" stroke-dasharray="4 3"/>
  <text x="68" y="270" font-size="12" font-weight="600" fill="#3C3489">On-device prediction &amp; safety engines</text>

  <rect x="66" y="280" width="150" height="34" rx="8" fill="#EEEDFE" stroke="#7F77DD" stroke-width="0.5"/>
  <text x="141" y="301" font-size="11.5" text-anchor="middle" fill="#26215C">FlowAnalysisEngine</text>

  <rect x="226" y="280" width="150" height="34" rx="8" fill="#EEEDFE" stroke="#7F77DD" stroke-width="0.5"/>
  <text x="301" y="301" font-size="11.5" text-anchor="middle" fill="#26215C">RiskPredictionEngine</text>

  <rect x="66" y="322" width="150" height="34" rx="8" fill="#EEEDFE" stroke="#7F77DD" stroke-width="0.5"/>
  <text x="141" y="343" font-size="11.5" text-anchor="middle" fill="#26215C">EvacuationRoutingEngine</text>

  <rect x="226" y="322" width="150" height="34" rx="8" fill="#EEEDFE" stroke="#7F77DD" stroke-width="0.5"/>
  <text x="301" y="343" font-size="11.5" text-anchor="middle" fill="#26215C">DigitalTwinProjection</text>

  <rect x="66" y="364" width="150" height="20" rx="6" fill="#F1EFE8" stroke="#B4B2A9" stroke-width="0.5"/>
  <text x="141" y="378" font-size="10" text-anchor="middle" fill="#444441">AlertDebouncer</text>

  <rect x="226" y="364" width="150" height="20" rx="6" fill="#F1EFE8" stroke="#B4B2A9" stroke-width="0.5"/>
  <text x="301" y="378" font-size="9.5" text-anchor="middle" fill="#444441">FoundationModels (on-device)</text>

  <line x1="240" y1="390" x2="240" y2="412" stroke="#7F77DD" stroke-width="1"/>

  <!-- Network clients -->
  <rect x="52" y="412" width="336" height="90" rx="12" fill="#ffffff" stroke="#AFA9EC" stroke-width="0.75" stroke-dasharray="4 3"/>
  <text x="68" y="432" font-size="12" font-weight="600" fill="#3C3489">Network clients</text>

  <rect x="66" y="442" width="150" height="46" rx="8" fill="#EEEDFE" stroke="#7F77DD" stroke-width="0.5"/>
  <text x="141" y="461" font-size="11.5" text-anchor="middle" fill="#26215C">APIClient / AuthService</text>
  <text x="141" y="477" font-size="10" text-anchor="middle" fill="#534AB7">REST + Cognito (Keychain)</text>

  <rect x="226" y="442" width="150" height="46" rx="8" fill="#EEEDFE" stroke="#7F77DD" stroke-width="0.5"/>
  <text x="301" y="461" font-size="11.5" text-anchor="middle" fill="#26215C">RealtimeClient</text>
  <text x="301" y="477" font-size="10" text-anchor="middle" fill="#534AB7">Persistent WebSocket</text>

  <rect x="52" y="512" width="336" height="58" rx="12" fill="#ffffff" stroke="#B4B2A9" stroke-width="0.75"/>
  <text x="68" y="533" font-size="11.5" fill="#444441">Also: LocationManager &#183; SensorIngestionService</text>
  <text x="68" y="551" font-size="11.5" fill="#444441">OfflineSyncManager (reachability) &#183; KeychainStore</text>

  <!-- ============ AWS CONTAINER ============ -->
  <rect x="470" y="30" width="460" height="560" rx="18" fill="#E6F1FB" stroke="#185FA5" stroke-width="1"/>
  <text x="492" y="60" font-size="15" font-weight="600" fill="#042C53">AWS backend (SAM / CloudFormation)</text>
  <text x="492" y="79" font-size="12" fill="#0C447C">ap-south-2 &#183; serverless, pay-per-use</text>

  <!-- Cognito -->
  <rect x="492" y="98" width="200" height="52" rx="10" fill="#F0997B" fill-opacity="0.25" stroke="#993C1D" stroke-width="0.75"/>
  <text x="592" y="119" font-size="13" font-weight="600" text-anchor="middle" fill="#4A1B0C">Cognito user pool</text>
  <text x="592" y="136" font-size="10.5" text-anchor="middle" fill="#712B13">Groups: Public &#183; Command</text>

  <!-- Bedrock -->
  <rect x="708" y="98" width="200" height="52" rx="10" fill="#F0997B" fill-opacity="0.25" stroke="#993C1D" stroke-width="0.75"/>
  <text x="808" y="119" font-size="13" font-weight="600" text-anchor="middle" fill="#4A1B0C">Amazon Bedrock</text>
  <text x="808" y="136" font-size="10.5" text-anchor="middle" fill="#712B13">Claude &#183; incident summaries</text>

  <!-- HTTP API -->
  <rect x="492" y="168" width="200" height="46" rx="10" fill="#85B7EB" fill-opacity="0.35" stroke="#185FA5" stroke-width="0.75"/>
  <text x="592" y="188" font-size="13" font-weight="600" text-anchor="middle" fill="#042C53">HTTP API</text>
  <text x="592" y="204" font-size="10.5" text-anchor="middle" fill="#0C447C">JWT-authorized (Cognito)</text>

  <!-- WebSocket API -->
  <rect x="708" y="168" width="200" height="46" rx="10" fill="#85B7EB" fill-opacity="0.35" stroke="#185FA5" stroke-width="0.75"/>
  <text x="808" y="188" font-size="13" font-weight="600" text-anchor="middle" fill="#042C53">WebSocket API</text>
  <text x="808" y="204" font-size="10.5" text-anchor="middle" fill="#0C447C">Live push channel</text>

  <!-- Lambda block -->
  <rect x="492" y="232" width="416" height="118" rx="12" fill="#ffffff" stroke="#85B7EB" stroke-width="0.75" stroke-dasharray="4 3"/>
  <text x="508" y="252" font-size="12" font-weight="600" fill="#0C447C">Lambda functions (Python 3.12, arm64)</text>

  <g font-size="11" fill="#042C53">
    <rect x="508" y="260" width="122" height="26" rx="6" fill="#B5D4F4" fill-opacity="0.4" stroke="#378ADD" stroke-width="0.5"/>
    <text x="569" y="277" text-anchor="middle">health</text>

    <rect x="640" y="260" width="122" height="26" rx="6" fill="#B5D4F4" fill-opacity="0.4" stroke="#378ADD" stroke-width="0.5"/>
    <text x="701" y="277" text-anchor="middle">venue-state</text>

    <rect x="772" y="260" width="122" height="26" rx="6" fill="#B5D4F4" fill-opacity="0.4" stroke="#378ADD" stroke-width="0.5"/>
    <text x="833" y="277" text-anchor="middle">alerts</text>

    <rect x="508" y="292" width="122" height="26" rx="6" fill="#B5D4F4" fill-opacity="0.4" stroke="#378ADD" stroke-width="0.5"/>
    <text x="569" y="309" text-anchor="middle">incidents</text>

    <rect x="640" y="292" width="122" height="26" rx="6" fill="#B5D4F4" fill-opacity="0.4" stroke="#378ADD" stroke-width="0.5"/>
    <text x="701" y="309" text-anchor="middle">recommendations</text>

    <rect x="772" y="292" width="122" height="26" rx="6" fill="#B5D4F4" fill-opacity="0.4" stroke="#378ADD" stroke-width="0.5"/>
    <text x="833" y="309" text-anchor="middle">venues</text>

    <rect x="508" y="324" width="122" height="22" rx="6" fill="#B5D4F4" fill-opacity="0.4" stroke="#378ADD" stroke-width="0.5"/>
    <text x="569" y="339" text-anchor="middle" font-size="10">summary (Bedrock)</text>

    <rect x="640" y="324" width="254" height="22" rx="6" fill="#B5D4F4" fill-opacity="0.4" stroke="#378ADD" stroke-width="0.5"/>
    <text x="767" y="339" text-anchor="middle" font-size="9.5">ws-connect &#183; ws-disconnect &#183; ws-broadcast &#183; post-confirmation</text>
  </g>

  <!-- DynamoDB -->
  <rect x="492" y="366" width="200" height="66" rx="10" fill="#97C459" fill-opacity="0.3" stroke="#3B6D11" stroke-width="0.75"/>
  <text x="592" y="387" font-size="13" font-weight="600" text-anchor="middle" fill="#173404">DynamoDB (7 tables)</text>
  <text x="592" y="403" font-size="10.5" text-anchor="middle" fill="#27500A">venues &#183; venue-state &#183; alerts</text>
  <text x="592" y="418" font-size="10.5" text-anchor="middle" fill="#27500A">incidents &#183; recommendations &#183; connections</text>

  <!-- Streams -->
  <rect x="708" y="366" width="200" height="66" rx="10" fill="#97C459" fill-opacity="0.3" stroke="#3B6D11" stroke-width="0.75"/>
  <text x="808" y="387" font-size="13" font-weight="600" text-anchor="middle" fill="#173404">DynamoDB Streams</text>
  <text x="808" y="403" font-size="10.5" text-anchor="middle" fill="#27500A">Change events fan out</text>
  <text x="808" y="418" font-size="10.5" text-anchor="middle" fill="#27500A">to ws-broadcast Lambda</text>

  <!-- Ops -->
  <rect x="492" y="452" width="416" height="60" rx="10" fill="#F1EFE8" stroke="#B4B2A9" stroke-width="0.75"/>
  <text x="700" y="474" font-size="12.5" font-weight="600" text-anchor="middle" fill="#2C2C2A">CloudWatch alarms</text>
  <text x="700" y="492" font-size="11" text-anchor="middle" fill="#444441">Per-function error alarms &#8594; SNS topic &#8594; email notification</text>

  <rect x="492" y="530" width="416" height="42" rx="10" fill="#ffffff" stroke="#B4B2A9" stroke-width="0.5"/>
  <text x="700" y="555" font-size="11" text-anchor="middle" fill="#5F5E5A">Free-tier by design: arm64 Lambda, provisioned 5/5 DynamoDB, TTL cleanup, no EC2/NAT/RDS</text>

  <!-- ============ CONNECTIONS BETWEEN CONTAINERS ============ -->
  <!-- HTTPS/REST: client network clients -> HTTP API -->
  <path d="M410 448 L470 191" fill="none" stroke="#5b6472" stroke-width="1.4" marker-end="url(#arrow)"/>
  <text x="418" y="300" font-size="11.5" fill="#2C2C2A">HTTPS / REST</text>
  <text x="418" y="315" font-size="10" fill="#5F5E5A">(JWT bearer</text>
  <text x="418" y="328" font-size="10" fill="#5F5E5A">token)</text>

  <!-- WebSocket: client RealtimeClient -> WebSocket API, arcs above the Lambda block (stays above y=225) -->
  <path d="M412 480 C 452 400, 452 195, 706 191" fill="none" stroke="#0f6e56" stroke-width="1.4" marker-end="url(#arrowTeal)"/>
  <text x="418" y="510" font-size="11.5" fill="#085041">wss:// live push</text>
  <text x="418" y="525" font-size="10" fill="#0F6E56">(token + venueId)</text>

  <!-- Legend -->
  <text x="30" y="608" font-size="10.5" fill="#5F5E5A">Purple = client app &#183; Blue = API layer &#183; Coral = auth / AI &#183; Green = data layer &#183; Gray = ops</text>
</svg>

<p align="center">
  <img src="docs/images/architecture-overview.svg" alt="CrowdShield system architecture: a SwiftUI client with on-device prediction engines talks to an AWS SAM backend (Cognito, HTTP API, seven Lambda functions, DynamoDB, WebSocket API, Bedrock, CloudWatch) over HTTPS and WebSocket" width="100%">
</p>

**Design principle:** every prediction engine on the client (risk, evacuation, flow, panic) works standalone on simulated/local sensor data, so the app is fully demoable offline. The AWS layer adds real auth, persistence, cross-device real-time sync, and a server-side LLM summary — but nothing about the safety logic *depends* on the network being up.

### How a change reaches every screen in real time

The most distinctive piece of the backend isn't any single Lambda — it's the DynamoDB Streams → broadcast fan-out that turns one write into a live update on every connected device, Public and Command alike, with no polling anywhere in the client:

<p align="center">
  <img src="docs/images/realtime-data-flow.svg" alt="Sequence diagram: a Command app POSTs an incident, an Incidents Lambda writes it to DynamoDB, the write triggers a DynamoDB Stream event, a ws-broadcast Lambda looks up subscribed connections for that venue in the Connections table, and pushes the update to every Public and Command device connected to that venue over WebSocket" width="100%">
</p>

This same path — write → stream → broadcast Lambda → connection lookup → push — is what drives live updates for venue state, alerts, incidents, *and* recommendations. It's one mechanism reused for every real-time feature in the app, rather than a bespoke pipeline per feature.

---

## Tech Stack

**Client**
- Swift 5, SwiftUI, Combine
- Targets iOS 26 / macOS 26 (Liquid Glass design system, Apple Foundation Models framework)
- RealityKit (Digital Twin 3D scene)
- Core Location, Vision, AVFoundation (speech), Network (reachability)
- Firebase (optional — gracefully no-ops if not linked via SPM)
- Native `URLSession`-based API/auth/realtime clients — no heavyweight networking dependency

**Backend**
- AWS SAM (CloudFormation under the hood), Python 3.12 Lambdas on `arm64`
- Amazon Cognito (User Pool, Essentials tier, custom PostConfirmation trigger)
- Amazon API Gateway — HTTP API (JWT-authorized REST) **and** WebSocket API (real-time push)
- Amazon DynamoDB (7 tables, Streams-driven fan-out)
- Amazon Bedrock (Claude, via a global cross-Region inference profile)
- Amazon CloudWatch Alarms + SNS (ops alerting)
- Amazon SES / SNS not used for notifications by design (see [Cost Model](#cost-model))

---

## Project Structure

```
CrowdShield/
├── CrowdShield/                     # iOS/macOS app target
│   ├── CrowdShieldApp.swift         # App entry point, environment wiring
│   ├── ContentView.swift            # Root view / role routing
│   ├── Models/
│   │   ├── CrowdModels.swift        # CrowdZone, RiskLevel, CrowdAlert, Recommendation, Venue…
│   │   ├── UserRole.swift           # UserRole enum + UserSession (auth/session state machine)
│   │   └── PrivacyPolicy.swift      # In-app privacy commitments (data, not just docs)
│   ├── Services/
│   │   ├── CrowdShieldAPIClient.swift        # REST client for the HTTP API
│   │   ├── CrowdShieldAuthService.swift      # Cognito sign-up/in/refresh/reset
│   │   ├── CrowdShieldRealtimeClient.swift   # WebSocket client for live push
│   │   ├── CrowdShieldConfig.swift           # Deployed stack endpoints/IDs
│   │   ├── CrowdSimulationService.swift      # Orchestrator: ties engines + services together
│   │   ├── RiskPredictionEngine.swift        # Stampede likelihood + panic propagation
│   │   ├── EvacuationRoutingEngine.swift     # Venue-graph shortest-safe-path routing
│   │   ├── FlowAnalysisEngine.swift          # Rolling-window trend detection
│   │   ├── DigitalTwinProjection.swift       # Lat/lon → 3D scene-space projection
│   │   ├── SensorIngestionService.swift      # Pluggable sensor sources (sim/vision/crowd)
│   │   ├── FoundationModelsSummaryProvider.swift  # On-device AI summaries (Apple Intelligence)
│   │   ├── IncidentSummaryService.swift      # Summary protocol + offline template provider
│   │   ├── AlertDebouncer.swift              # Persistence + cooldown alert gating
│   │   ├── OfflineSyncManager.swift          # Network reachability monitor
│   │   ├── KeychainStore.swift               # Secure refresh-token/email storage
│   │   ├── LocationManager.swift             # Core Location wrapper
│   │   └── HapticManager.swift               # Haptic feedback for alerts/actions
│   └── Views/                        # ~15 SwiftUI views: dashboards, map, alerts, digital twin,
│                                      # multilingual assistant, privacy screen, role/venue selection…
├── CrowdShieldTests/                 # XCTest unit tests (engines)
├── aws/                               # Serverless backend (AWS SAM)
│   ├── template.yaml                 # Full infra-as-code: Cognito, API GW, Lambdas, DynamoDB, alarms
│   ├── samconfig.toml                # SAM CLI deploy configuration
│   ├── src/
│   │   ├── health/                   # GET /health
│   │   ├── venue_state/              # GET/PUT /venues/{id}/state
│   │   ├── alerts/                   # GET/POST /venues/{id}/alerts
│   │   ├── incidents/                # GET/POST /venues/{id}/incidents
│   │   ├── recommendations/          # GET/POST /venues/{id}/recommendations
│   │   ├── venues/                   # GET/POST /venues (registry)
│   │   ├── summary/                  # POST /venues/{id}/summary (Bedrock)
│   │   ├── post_confirmation/        # Cognito trigger — auto-assigns Public group
│   │   ├── ws_connect/ ws_disconnect/ ws_broadcast/   # WebSocket lifecycle + fan-out
│   │   └── shared/                   # Common helpers (JWT verification, response shaping)
│   └── tests/                        # pytest unit tests (e.g. venue-slug generation)
└── CrowdShield.xcodeproj/
```

---

## Getting Started

### iOS/macOS App

**Requirements:** Xcode with iOS 26 / macOS 26 SDKs, a physical device or Apple Silicon Mac recommended (RealityKit Digital Twin and Apple Foundation Models features need real hardware, not the simulator).

```bash
git clone https://github.com/guguluP/CrowdShield.git
cd CrowdShield
open CrowdShield.xcodeproj
```

1. Build and run the `CrowdShield` scheme.
2. The app ships pointed at a live deployed backend (see `CrowdShieldConfig.swift`) — you can run it immediately against that stack, or deploy your own (below) and update the constants there.
3. Firebase is optional: the app checks `#if canImport(FirebaseCore)` and simply skips initialization if the SDK isn't linked — no crash, no required setup.
4. Sign up as a **Public** user directly in-app (self-signup → email confirmation → auto-added to the `Public` Cognito group). **Command** accounts are provisioned manually (by design — see [Backend API Reference](#backend-api-reference)); add a user to the `Command` group via the Cognito console or CLI to test that role.

### AWS Backend

The backend is a complete AWS SAM application. Deploying your own stack is optional — the app already points at a live one — but useful if you want your own data, your own Bedrock quota, or to extend the API.

**Prerequisites**
- An AWS account
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html), configured (`aws configure`)
- [AWS SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html)
- Bedrock model access enabled for the Claude model referenced in `template.yaml` (`BedrockModelId` parameter), if you want AI summaries

```bash
cd aws
sam build
sam deploy --guided
```

On subsequent deploys:

```bash
sam build && sam deploy
```

SAM prints stack **Outputs** when it finishes — `ApiEndpoint`, `WebSocketUrl`, `UserPoolId`, `UserPoolClientId`, and per-resource URL templates. Copy the relevant ones into `CrowdShield/Services/CrowdShieldConfig.swift`.

**Quick health check:**

```bash
curl "$(aws cloudformation describe-stacks \
  --stack-name crowdshield-phase1 \
  --query "Stacks[0].Outputs[?OutputKey=='HealthUrl'].OutputValue" \
  --output text)"
```

**Tear down:**

```bash
sam delete --stack-name crowdshield-phase1
```

> The `aws/README.md` and `aws/README-UPDATE.md` files in this repo capture the incremental deploy history (Phase 1 foundation → later phases) in more granular detail, including console-only update steps if you don't have the SAM CLI handy.

---

## Backend API Reference

All routes are served from one HTTP API (`AWS::Serverless::HttpApi`), JWT-authorized against the Cognito User Pool by default; `/health` is the only public, unauthenticated route.

| Method | Path | Auth | Notes |
|---|---|---|---|
| `GET` | `/health` | None | Liveness + DynamoDB connectivity check |
| `GET` / `PUT` | `/venues/{venueId}/state` | Any authenticated user | Live crowd/venue state |
| `GET` / `POST` | `/venues/{venueId}/alerts` | Any authenticated (POST is Command-only, enforced in code) | |
| `GET` / `POST` | `/venues/{venueId}/incidents` | Any authenticated user may POST | Public incident reporting |
| `GET` / `POST` | `/venues/{venueId}/recommendations` | Any authenticated (POST is Command-only, enforced in code) | |
| `GET` / `POST` | `/venues` | Any authenticated (POST is Command-only, enforced in code) | Venue registry; `POST` creates a venue and derives its slug `venueId` |
| `POST` | `/venues/{venueId}/summary` | Any authenticated user | Triggers a Bedrock-generated incident summary |

**Real-time:** connect to `wss://{WebSocketApi}/{stage}?token=<Cognito ID token>&venueId=<venue id>`. The backend verifies the token on `$connect`, tracks the connection in a DynamoDB table (with a `byVenue` GSI), and a dedicated broadcast Lambda — driven by DynamoDB Streams off the venue-state, alerts, incidents, and recommendations tables — pushes every change to every connection subscribed to that venue, in near real time.

**Role enforcement:** Cognito groups (`Public`, `Command`) are embedded in the JWT. Self-signup always lands a user in `Public` via a `PostConfirmation` Lambda trigger; `Command` is never auto-assigned and must be granted manually — there is deliberately no self-service path to operator access.

---

## The Prediction Engines

CrowdShield's headline claim — *predicting* stampede risk rather than reacting to it — lives in a small set of composable engines:

- **`FlowAnalysisEngine`** keeps a rolling history (last 8 samples) per zone and computes density trend (people/m² per second). This is what turns "density is high" into "density is high **and rising fast**" — the actual leading indicator.
- **`RiskPredictionEngine`** combines density, mobility collapse, flow anomalies, and that trend into an explicit `StampedePrediction` (0–1 likelihood, primary drivers, estimated minutes-to-critical) per zone, plus a `PanicState` that models how panic intensity seeds and spreads across the venue's connectivity graph.
- **`EvacuationRoutingEngine`** walks a modeled `VenueGraph` (gates, plazas, stands, bottlenecks, and their real connectivity/distances) to compute the nearest safe-exit path from any zone — so every high-risk reading can be paired with an actionable route, not just a warning.
- **`DigitalTwinProjection`** turns each zone's real (lat, lon) into a flat, geographically-accurate 3D scene position (equirectangular-style local projection), which `DigitalTwinView` then renders live in RealityKit with column height and color both driven by current risk.
- **`AlertDebouncer`** sits on top of all of the above: a condition needs to persist for multiple consecutive ticks before it's treated as real, and once an alert fires for a given key it won't re-fire again until a cooldown elapses — directly addressing false-alarm fatigue rather than leaving every engine to reinvent its own noise filter.

All of this runs identically whether the underlying zone data comes from the built-in simulator, on-device Vision-based density estimation, or (in a future phase) real venue sensors — see `SensorIngestionService`'s `SensorSource` protocol.

---

## Privacy & Ethics by Design

Crowd-safety systems live or die on public trust, so CrowdShield treats privacy as a first-class, user-visible feature (`PrivacyEthicsView`), not a buried policy page:

- **No raw imagery ever leaves the device** — on-device Vision-based density estimation processes frames in memory and discards them immediately.
- **No facial recognition or identity tracking** — people are counted as anonymous bounding boxes for density/flow only.
- **Aggregate numbers only** cross the network — density, speed, flow direction, risk score. None of it can be reversed into an image or an identity.
- **Citizen reports are opt-in and can be anonymous.**
- **Minimal retention** — zone telemetry is kept only as a short rolling window needed for trend prediction.
- **Compliant by design** — architecture avoids collecting PII by default, in line with data-minimization principles under India's Digital Personal Data Protection Act, 2023.

---

## Testing

- **Swift (XCTest)** — `CrowdShieldTests/` covers the alert debouncer's persistence/cooldown logic, the digital twin's geographic projection math, and the evacuation routing engine's pathfinding over the venue graph.
- **Python (pytest)** — `aws/tests/` covers backend logic such as venue-name-to-slug generation for the venue registry.

Run iOS tests via Xcode's Test navigator or `xcodebuild test`; run backend tests with `pytest aws/tests/`.

---

## Cost Model

The backend is deliberately architected to stay inside AWS's Always Free tier for demo-scale traffic:

- No EC2, NAT Gateway, RDS, or SMS.
- DynamoDB tables are provisioned well under the free 25 RCU/WCU (5/5 each).
- Cognito Essentials tier: free for typical demo MAU volumes.
- Lambda runs on `arm64` at 128 MB — cheapest available compute shape.
- TTL is enabled on time-bounded tables (alerts, incidents, connections) so demo data doesn't accumulate indefinitely.
- CloudWatch Alarms feed a single SNS topic with email delivery — no per-message SMS cost.

The only paid-by-design piece is Bedrock model invocation for AI summaries, which is pay-per-request and only triggered on demand.

---

## Roadmap

Ideas that fit naturally into the existing architecture but aren't built yet:
- Real venue sensor integrations (beyond the simulated/on-device Vision sources already abstracted behind `SensorSource`)
- Historical analytics / post-event reporting beyond the current rolling-window retention
- Push notifications (APNs) layered on top of the existing WebSocket channel for background alerting
- Passkey (WebAuthn) sign-in once an Apple Developer Program Associated Domains entitlement and hosting are in place (the Cognito user pool is already provisioned on the Essentials tier that supports it)

---

## License

No license file is currently published in this repository — until one is added, all rights are reserved by the author. Open an issue or contact [@guguluP](https://github.com/guguluP) if you'd like to use this project beyond personal reference.
