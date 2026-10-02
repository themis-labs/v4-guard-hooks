# v4 Guard Hooks

Uniswap v4 hooks that enforce Aegis trading-permission state at the execution
layer.

[Aegis](https://github.com/themis-labs/tsv-aegis) tracks reference-market halt
status and venue-level trading conditions on-chain behind a single check,
`tradingEnabled()`. The hooks in this repo wire that check into Uniswap v4
pools: a swap against a guarded pool reverts atomically while the guard reads
as trading-disabled, so a tokenized asset cannot keep trading on-chain through
a halt of its reference market.

The first hook under development is `LULDGuardHook`: a thin `beforeSwap`
interceptor that reads guard state and holds no market state of its own.
Session-aware and per-pool volume variants are being evaluated against the
same single-source-of-truth rule — hooks read, the guard decides.

## Status

Early development. No deployments yet. The companion guard contract is live
on Base mainnet, Base Sepolia, and Arbitrum Sepolia; see the Aegis repo for
deployment records.

## Disclaimer

This project is open-source developer tooling and a reference implementation.
It does not operate a trading venue, issue securities, provide brokerage
services, custody assets, perform KYC/AML, or guarantee regulatory compliance.
Any deployment uses simulated events and test assets unless explicitly
documented otherwise.

## License

MIT
