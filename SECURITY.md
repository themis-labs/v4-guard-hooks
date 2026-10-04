# Security Policy

## Reporting a vulnerability

Please report vulnerabilities through GitHub's private vulnerability
reporting ("Report a vulnerability" on the Security tab). Do not open public
issues for unpatched security problems.

## Scope

The hooks are thin interception contracts: they hold no funds and keep no
market state. The most relevant findings are bypasses of the `beforeSwap`
permission check, incorrect hook permission bits, and failure modes where a
disabled guard state does not block a swap.

The contracts currently documented under "Status" in the README are deployed
on test networks with test assets. No deployment should be treated as
production infrastructure.

## Response

This project is maintained by a small independent team. There is no bug
bounty program at this time. Reports are acknowledged and triaged as time
permits, and credited in the fix commit unless the reporter prefers
otherwise.
