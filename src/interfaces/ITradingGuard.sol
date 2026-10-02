// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal trading-permission surface consumed by the hooks.
///         One guard instance answers for one asset; the check takes no
///         arguments by design. Implementations are expected to fail
///         closed: any uninitialized, halted, stale, or over-limit state
///         must read as trading-disabled. The Aegis TSVGuard contract is
///         the reference implementation.
interface ITradingGuard {
    /// @notice Whether the guarded asset may trade right now.
    function tradingEnabled() external view returns (bool);
}
