# Secure CI/CD demo

A small website with a pipeline that tests it, scans it, and publishes it to
AWS, protected by eight safeguards you can each try to break. Setup and tests
take about 30 minutes.

## The eight safeguards

| Safeguard | In plain English | Where it lives | How you test it |
|---|---|---|---|
| Automated testing and deployment | A robot checks every change and publishes the good ones | `.github/workflows/pipeline.yml`, `tests/check.sh` | Push a change, watch it go live |
| OIDC authentication | The robot signs in with a 15-minute visitor pass, not a stored key | `infra/main.tf` (trust policy), the "Sign in to AWS" step | No AWS key exists in GitHub, and a pull request is refused |
| IAM least privilege | The pass opens one door: the site's storage bucket | `infra/main.tf` (role policy), `tests/least_privilege.sh` | The pipeline tries five other things and AWS refuses each |
| Secrets management | Passwords live in a vault, never in the code | GitHub Actions secrets, `tests/secret_scan.sh` | The Slack address shows as `***` in logs, and a hard-coded password is blocked |
| Branch protection | Nobody, including the owner, can skip the checks | GitHub ruleset on `main` | A direct push to `main` is rejected |
| Vulnerability scanning | Third-party ingredients are checked against a recall list | The `pip-audit` step | A change that uses a known-vulnerable library is blocked |
| Slack alerts | The team is told about every pass and every block | `scripts/notify.sh` | A green and a red message arrive in Slack |
| Audit logging | AWS keeps its own record of every sign-in | AWS CloudTrail, `audit.sh` | The record shows which pipeline run signed in, and when |

## What you need

- A GitHub account, and `git` on your computer
- An AWS account, with the AWS CLI signed in as a user who can create IAM roles, S3 buckets and CloudFront distributions
- Terraform (`brew install hashicorp/tap/terraform` on a Mac)
- A Slack workspace where you can add an app

Cost: effectively nothing. A few kilobytes in S3 and a handful of CloudFront requests.

## Setup

### 1. Create the repository (1 min)

Go to <https://github.com/new>. Name it `secure-cicd-demo`, set it to
**Public**, leave every checkbox empty, and click **Create repository**.

It has to exist before the next step, because AWS is going to be told to trust
this exact repository by its permanent ID. It has to be public because branch
protection is free only on public repositories.

### 2. Build the AWS side (1 min of typing, about 4 min of waiting)

In a terminal, from inside this folder:

```bash
bash setup.sh YOUR-USERNAME/secure-cicd-demo
```

This creates a private storage bucket, a CloudFront address that serves it over
HTTPS, a trust relationship with GitHub, and a role for the pipeline that can
write to that one bucket. It ends by printing three values. Leave the terminal
open and carry on with step 3 while it runs.

### 3. Create the Slack alert address (3 min)

1. Open <https://api.slack.com/apps?new_app=1>, choose **From scratch**, name it `Pipeline alerts`, pick your workspace, click **Create App**.
2. In the left menu click **Incoming Webhooks** and switch **Activate Incoming Webhooks** on.
3. Click **Add New Webhook to Workspace**, pick a channel, click **Allow** (it may say **Authorize**).
4. Copy the **Webhook URL**. Treat it like a password: anyone holding it can post to your channel.

### 4. Give GitHub two secrets and two variables (3 min)

In the repository: **Settings > Secrets and variables > Actions**.

- **Secrets** tab, **New repository secret**, twice:
  - `SLACK_WEBHOOK_URL`: the URL from step 3.
  - `AWS_ROLE_ARN`: the value `setup.sh` printed.
- **Variables** tab, **New repository variable**, twice: `S3_BUCKET` and `SITE_URL`, with the values `setup.sh` printed.

If `setup.sh` said it saved its three values for you, only the Slack secret is left to add.

A secret is hidden forever once saved, even from you, and GitHub replaces it
with `***` in every log. The Slack address is a real secret: anyone holding it
can post to your channel. The role address is not a password, but it contains
your AWS account number and this repository's logs are public, so it is kept
out of them. Notice what is missing from both lists: there is no AWS key.

### 5. Push the project (2 min)

```bash
git init -b main
git add .
git commit -m "First release"
git remote add origin https://github.com/YOUR-USERNAME/secure-cicd-demo.git
git push -u origin main
```

Open the **Actions** tab and watch the run. When it is green, open your
`SITE_URL`: the page shows Release #1. A green message arrives in Slack.

### 6. Lock the main branch (3 min)

**Settings > Rules > Rulesets > New ruleset > New branch ruleset.**

1. Ruleset name: `protect-main`. Enforcement status: **Active**.
2. Target branches: **Add target > Include default branch**.
3. Tick **Restrict deletions** and **Block force pushes** (usually ticked already).
4. Tick **Require a pull request before merging**. Leave required approvals at 0, since you are working alone. On a team this would be 1 or more.
5. Tick **Require status checks to pass**, click **Add checks**, type `Test and scan`, select it.
6. Click **Create**.

From now on the only way onto `main` is a pull request whose checks are green.

## The tests

### Test 1. Read the first run (2 min): OIDC, least privilege, secrets

Open run #1 in the Actions tab and click **Deploy to AWS**.

- **Sign in to AWS with a 15-minute pass**: no key was supplied. GitHub vouched for the run and AWS issued a temporary pass.
- **Show who the pipeline is signed in as**: the role name, followed by `release-1`.
- **Prove the pipeline cannot do anything else in AWS**: five lines of `PASS  Refused`.

Then click **Tell the team on Slack** and open **Send the Slack alert**. The
webhook address appears as `***`.

### Test 2. Try to skip the checks (1 min): branch protection

```bash
git commit --allow-empty -m "Sneak past the checks"
git push
```

GitHub rejects the push with `GH013: Repository rule violations`. Undo the
local commit with `git reset --hard origin/main`.

### Test 3. Propose a change with a known-vulnerable library (4 min): scanning, alerts, OIDC lockdown

1. On GitHub, open `requirements.txt` and click the pencil.
2. Change `jinja2==3.1.6` to `jinja2==3.1.2`.
3. Click **Commit changes**. GitHub will only let you create a new branch and start a pull request. Do that, then click **Create pull request**.

Within a minute:

- **Test and scan** fails. Open it: the scan lists the known vulnerabilities in that version.
- **Prove pull requests cannot reach AWS** passes. Open it: the sign-in step shows the error "Not authorized to perform sts:AssumeRoleWithWebIdentity", and the next step prints `PASS  AWS refused`.
- The **Merge** button is blocked.
- A red message arrives in Slack.
- The live site has not changed.

Click **Close pull request**.

### Test 4. Ship a good change the proper way (3 min): the whole path

1. Open `site/index.html.j2`, click the pencil, change the text between `<h1>` and `</h1>`.
2. Commit to a new branch, create the pull request, wait for both checks to go green.
3. Click **Merge pull request**, then **Confirm merge**.

A new run starts on `main`, deploys, and Slack announces the release. Refresh
the site.

### Test 5. Read the audit log (1 min): audit logging

```bash
bash audit.sh
```

Each row is a sign-in that AWS recorded: the time, the pipeline run (for
example `release-1` and `release-4`), and the identity GitHub presented. If AWS
recorded the refused pull-request attempt, it shows as `REFUSED`. Records can
take up to 15 minutes to appear, which is why this test is last.

### Optional. Commit a password

Through a pull request, add a file `config.py` containing:

```python
DB_PASSWORD = "SuperSecret123"
```

**Test and scan** fails at "Scan the code for passwords and keys". The log
names the file and line, and does not print the password.

## Clean up

```bash
bash teardown.sh
```

Then delete the Slack app at <https://api.slack.com/apps> and, if you like, the
repository.

## If something goes wrong

- **`Not authorized to perform sts:AssumeRoleWithWebIdentity` on the main branch.** AWS does not recognise the identity GitHub presented. Check that you ran `setup.sh` with the exact repository name, and that the repository was not renamed afterwards. Re-running `setup.sh` refreshes the trust.
- **The deploy job cannot find the role, bucket or site.** `AWS_ROLE_ARN` must be under Secrets; `S3_BUCKET` and `SITE_URL` must be under Variables. Check the names for typos.
- **No Slack message.** The run shows a warning if `SLACK_WEBHOOK_URL` is missing. A 404 means the URL was pasted incompletely.
- **`setup.sh` fails on CloudFront with "account must be verified".** New AWS accounts sometimes need this. AWS Support lifts it on request.
- **The scan fails on the first run.** A vulnerability may have been published for a pinned library since this project was written. Raise the version in `requirements.txt` to the one the scan recommends.

## Run it on your own computer

```bash
python3 -m venv .venv && . .venv/bin/activate
pip install -r requirements.txt
python3 build.py
bash tests/check.sh dist
bash tests/secret_scan.sh
```
