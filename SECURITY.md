# Security Policy

## Supported Versions

This project is pre-1.0. Security fixes are handled on the `main` branch and released as patch releases when public release artifacts exist.

## Reporting A Vulnerability

Please do not open a public issue for a vulnerability that could expose secrets, user data, or remote execution paths.

Until a dedicated security contact is configured for the GitHub repository, report vulnerabilities by opening a private security advisory on GitHub after the repository is created.

Include:

- Affected commit, tag, or release.
- Reproduction steps.
- Impact and affected data.
- Whether tokens, local databases, or synced third-party services are involved.

## Secret Handling

Never commit:

- LLM API keys.
- Notion integration tokens.
- Zotero API keys.
- Local SQLite databases.
- `runtime-settings.json`.
- Signed release credentials, provisioning profiles, certificates, or notarization credentials.

The app stores provider and integration secrets in Keychain. Runtime settings and local databases are user-local state and are ignored by `.gitignore`.

## Third-Party Services

When enabled, ArxivResearch can send paper abstracts and extracted full text to configured LLM providers. It can also sync metadata and notes to Notion and Zotero. Treat these integrations as explicit data egress paths.
