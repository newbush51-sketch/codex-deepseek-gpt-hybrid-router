
# Security

## Secrets

- Never commit `DEEPSEEK_API_KEY`, OpenAI credentials, Codex auth files, cookies, or logs.
- Store the DeepSeek key only as a Windows user environment variable.
- Keep every local service bound to `127.0.0.1`.
- Review generated `hybrid-models.json` before sharing it; it is intentionally gitignored.

## Reporting

Please open a GitHub security advisory for vulnerabilities. Do not include live API keys,
cookies, account IDs, or unredacted logs in an issue.


