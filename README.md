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

Live deployment on Base Sepolia (chain id 84532), 2026-10-03: hook
[0x3160E4eec2eaF776E0e3e4Ca0eB5931C350Bc080](https://sepolia.basescan.org/address/0x3160E4eec2eaF776E0e3e4Ca0eB5931C350Bc080)
(source verified on Basescan) bound to guard
0xBAcaF3d2765dcc314ee22CB19b87Cf755f5A6433, deploy tx
[0x83280b21fc583bf403f47de1253e501c840f650f7430962c258c0c0a0e3ccfb8](https://sepolia.basescan.org/tx/0x83280b21fc583bf403f47de1253e501c840f650f7430962c258c0c0a0e3ccfb8),
salt 0x1313, deployer 0x84E2E8BC8d5F511f60774f2191d1149ca0dd3643.

Live swap drill on Base Sepolia, 2026-10-03, against the deployment above:
pool 0x6b43bb1ad71ed2f34c098fc0d3bab4b5d7c488c6cb1fe7fcf73b4a3fcae94b4d
(token0 0x21441d14036f3dcbb0f268a0d4d6e7d965f5ae0a, token1
0x930cab20fce30061905dc6220ca3e31c4beb406b, fee 3000). Seed
[0x2a451558250183748a2d8b9f86a4f85081eaeef13b0596859216ccd4d93ad1f0](https://sepolia.basescan.org/tx/0x2a451558250183748a2d8b9f86a4f85081eaeef13b0596859216ccd4d93ad1f0),
Swap#1
[0x2fc64a7ff15c086e0aec223bfc6096c6c0c322265f2d53a11957767c73eff710](https://sepolia.basescan.org/tx/0x2fc64a7ff15c086e0aec223bfc6096c6c0c322265f2d53a11957767c73eff710)
(settled), halt
[0xdd756cad189a5fee8a7ddd0c674fef72d73394b1545d35cabeec8f4ef4ade82c](https://sepolia.basescan.org/tx/0xdd756cad189a5fee8a7ddd0c674fef72d73394b1545d35cabeec8f4ef4ade82c),
intercepted Swap#2
[0x1bc04996a7f282f3772be4df904d57f816dbe92539530e04fbb116e2ed786e75](https://sepolia.basescan.org/tx/0x1bc04996a7f282f3772be4df904d57f816dbe92539530e04fbb116e2ed786e75)
(status 0, the expected block), resume
[0xfb7637ffa5f621f6264c9a5c2424b51cfa35fbc07a452a6ea96c1b580cd1d096](https://sepolia.basescan.org/tx/0xfb7637ffa5f621f6264c9a5c2424b51cfa35fbc07a452a6ea96c1b580cd1d096),
Swap#3
[0x8f4caea6ef7eee16317888e915c7f5866502cde044eed98dc17c0fc8a85c0829](https://sepolia.basescan.org/tx/0x8f4caea6ef7eee16317888e915c7f5866502cde044eed98dc17c0fc8a85c0829)
(settled).

## Disclaimer

This project is open-source developer tooling and a reference implementation.
It does not operate a trading venue, issue securities, provide brokerage
services, custody assets, perform KYC/AML, or guarantee regulatory compliance.
Any deployment uses simulated events and test assets unless explicitly
documented otherwise.

## License

MIT
