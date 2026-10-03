# v4 Guard Hooks

Compliance and risk-control hooks for Uniswap v4 pools, driven by an external
trading-permission guard.

Each guarded pool delegates its go/no-go decision to a guard contract behind a
minimal interface, `ITradingGuard.tradingEnabled()`. The hooks hold no market
state of their own: they read the guard at swap time and revert atomically
when trading is disabled. Any contract implementing the interface can serve as
the guard — market-status oracles, venue policy engines, allowlist services.

[Aegis](https://github.com/themis-labs/tsv-aegis) is the reference guard
implementation: it tracks reference-market halt status and venue-level trading
conditions on-chain, with deployments on Base mainnet, Base Sepolia, and
Arbitrum Sepolia. The hooks work with it out of the box, and with any other
guard that honors the interface.

The first hook is `LULDGuardHook`: a thin `beforeSwap` interceptor that reads
guard state and holds none of its own. Session-aware and per-pool volume
variants are being evaluated against the same single-source-of-truth rule —
hooks read, the guard decides.

## Status

LULDGuardHook is implemented and covered by Foundry tests, including end-to-end
verification on a Base Sepolia fork against the live PoolManager and guard.
No deployments have been made.

## Disclaimer

This project is open-source developer tooling and a reference implementation.
It does not operate a trading venue, issue securities, provide brokerage
services, custody assets, perform KYC/AML, or guarantee regulatory compliance.
Any deployment uses simulated events and test assets unless explicitly
documented otherwise.

## License

MIT
