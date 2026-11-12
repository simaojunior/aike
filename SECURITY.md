# Security policy

Aike is a proof of concept for study. It is not for production, and nobody audited it.
Do not use it with real personal data.

## Supported versions

Only the `main` branch gets security fixes.

## How to report a vulnerability

Do not open a public issue. Use the private report of GitHub:

1. Open the **Security** tab of the repository.
2. Choose **Report a vulnerability**.
3. Describe the problem, the steps to reproduce it and the impact.

Do not include real documents or personal data in the report. Use synthetic data.

I answer as soon as I can and keep in touch until the fix. This is a project that one
person maintains, so there is no guaranteed response time.

## Scope

In scope: authentication and scopes, isolation between companies, personal data in logs,
errors or queues, and unsafe handling of uploaded files.

Out of scope: denial of service by volume, and flaws in dependencies without an
exploitable use in this project. Report dependency flaws to the upstream project.
