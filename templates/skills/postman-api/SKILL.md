---
name: postman-api
description: Call Pratilipi service APIs (Recommendation-Next, Khoj-Next, Content Services) through the Postman CLI using the team workspace collections and stage or prod environments. Handles VPN reachability.
---

# Postman API calls

Use the `postman` CLI. Workspace: `b0a149fb-80c9-4e8b-8916-bcebf4f54290`.
Run `postman whoami` if a command fails on auth; if not logged in, ask the user to run `postman login`.

## Collections

| Service | Collection ID |
| --- | --- |
| Content Services | `31954062-2fb8ad94-7843-4157-94d6-fcb684004ab6` |
| Khoj Next Service | `31954062-d344f1b8-36a5-40d2-921e-145114c87e64` |
| Other Services | `31954062-5885a4ea-9c03-411c-987a-1d36825d8983` |
| Recommendation-Next | `31954062-d4de22e2-5469-41dc-99d6-d223e1bc2678` |

## Environments

Use prod unless the user asks for stage.

| Environment | ID |
| --- | --- |
| Recommendation-Next Stage | `31954062-249b52eb-0fc1-4ab7-bafa-2f8bb1ceea6b` |
| Recommendation-Next Prod | `31954062-168d02f1-8feb-4bba-a65d-15860cfaf67b` |
| Khoj-Next - Stage | `31954062-f65f0484-c923-457b-a461-f34a7382c120` |
| Khoj-Next - Prod | `31954062-eb0a772c-5f3a-42f0-a62e-ec81240982fd` |

Local and gamma environments exist; run
`postman environment list --workspace b0a149fb-80c9-4e8b-8916-bcebf4f54290`
only when the user asks for one. If a collection or environment is missing, list the workspace again rather than guessing an ID.

## Find and call a request

Read the collection for paths, headers, and variables:

```bash
postman collection get <collection-id> --json
postman environment get <environment-id>
```

Prefer running a saved request or folder by its item `id` from the JSON. This resolves both collection and environment variables. Request names contain `/` (for example `GET /health`), so `Folder/Request` paths do not work; use the ID, or the bare name when it is unique.

```bash
postman collection run <collection-id> -e <environment-id> -i <request-id> --timeout-request 15000
```

For an ad hoc call or different parameters, use `postman request`. It resolves only environment variables such as `{{baseUrl}}`, so fill in collection values like `userId` yourself:

```bash
postman request GET '{{baseUrl}}/health' -e <environment-id> --timeout 15000
```

Ask before any request that creates, updates, or deletes data, in any environment.
On prod, make read-only calls only, unless the user approves a specific write.
Do not edit cloud collections or environments.
Do not print secret values or use `--show-secrets` unless the user asks. If a required token is empty, ask the user for it; never write it into a repository.

## VPN

These services are on private internal addresses and need the company VPN.
The user is usually connected to ProtonVPN instead.

Always try the call first. An HTTP response of any status means the service is reachable; debug it as an API result, not a VPN issue.

A timeout (`ETIMEDOUT`, or `Request failed: callback timed out` from `postman request`) or a connection error such as `ECONNREFUSED`, `EHOSTUNREACH`, or `ENOTFOUND` usually means the wrong VPN. Then stop: tell the user which host was unreachable and ask them to switch to the company VPN. Retry once after they confirm. Never change network or VPN settings yourself, and do not loop on retries.

Report the method, URL path, environment, status, and the relevant part of the response. Summarize large bodies.
