---
name: stage-local-run
description: Run a staging service, worker, or program on the local machine with the stage AWS profile and the service's private stage env file, to test changes before pushing.
---

# Run a stage service locally

Stage only. Never run against prod or use a prod profile.

## AWS access

Use the profile `ptlp-jit-stage-admin` (region `ap-south-1`). Check it first:

```bash
aws sts get-caller-identity --profile ptlp-jit-stage-admin
```

If it fails or the token has expired, ask the user to refresh their AWS
credentials and wait. Never read, print, copy, or edit `~/.aws/credentials`.
Pass the profile as `AWS_PROFILE`; never export access keys.

## Env files

Env files live outside every repository and workspace:

```text
~/.config/agent-envs/<service>.stage.env
```

`<service>` is the repository name. List the directory to find the file; do
not guess a near match. If it is missing, ask the user to create it there
with `chmod 600`. Never ask them to paste env values into the chat.

Never print env values, copy the file into a repository, or commit it.
Do not edit the file; report a broken value to the user instead.

## Run

Load the env file and profile for one command only:

```bash
(set -a && . ~/.config/agent-envs/<service>.stage.env && set +a && \
  AWS_PROFILE=ptlp-jit-stage-admin AWS_REGION=ap-south-1 <start command>)
```

Find the start command in the repository's README, `package.json`, `Makefile`,
`Dockerfile`, or ECS task definition. If the service only reads `.env` from its
own directory, prefer its env-file option (for example `node --env-file` or
`docker run --env-file`). Copy to `.env` only when `git check-ignore .env`
confirms it is ignored, and delete the copy when done.

If the env file does not source cleanly (for example unquoted spaces), stop
and tell the user which line number fails without showing its value.

## Shared stage resources

A local worker shares stage queues, topics, and databases with the deployed
stage tasks. Ask before starting a worker that consumes a shared queue or
before any run that creates, updates, or deletes stage data.

If a database, cache, or internal host is unreachable, ask the user to switch
to the company VPN and wait. Never change network or VPN settings yourself.

Stop background processes you started when testing is done.
