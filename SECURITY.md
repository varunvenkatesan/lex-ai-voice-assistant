# Security Policy

## Secrets

Never commit `.env`, API keys, LiveKit credentials, Gmail app passwords, private keys, or local user data. Use `.env.example` for placeholder names only, and configure real values in Render or local environment variables.

If a secret is exposed:

1. Revoke or rotate it immediately with the provider.
2. Remove it from the repository.
3. If it was committed, rewrite the affected Git history before making the repository public.

## Reporting

For private deployments, report security issues directly to the repository owner.
