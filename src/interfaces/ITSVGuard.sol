// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Minimal integration surface of the Aegis guard (TSVGuard).
///         One guard instance tracks one asset's trading permission;
///         tradingEnabled() takes no arguments by design.
interface ITSVGuard {
    /// @notice Whether trading is currently allowed. Fail-closed: reads as
    ///         disabled before the first oracle report, while halted, and
    ///         once the daily volume cap is reached.
    function tradingEnabled() external view returns (bool);
}
