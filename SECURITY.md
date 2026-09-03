# Security Policy

## Supported versions

The `main` branch is the only actively maintained line while this project is in early development.

## Reporting a vulnerability

Please do not open a public issue for a suspected vulnerability. Contact the repository owner privately through the contact method shown on the GitHub profile, and include:

- a short description and impact;
- reproducible steps without sharing real credentials;
- affected iOS version, app revision and deployment type;
- a safe way to reproduce using a redacted or local test instance.

Never send passwords, API keys, cookies, provisioning profiles or private server logs in an issue or pull request.

## Security notes for users

This app can load HTTP because private LAN deployments may need it. HTTP is plaintext and must not be used for an exposed public service. Prefer HTTPS or a private encrypted network such as a VPN/Tailscale. The app does not validate or bypass TLS certificate trust; use a certificate trusted by iOS for HTTPS deployments.
