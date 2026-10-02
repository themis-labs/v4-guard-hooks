// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

import {ITradingGuard} from "./interfaces/ITradingGuard.sol";

/// @notice Blocks swaps while the bound guard reports trading as disabled.
///
/// @dev Thin interception point between the pool manager and the guard. The
/// hook keeps no market state of its own: halt status lives solely in the
/// guard, so there is no second ledger to drift out of sync. One hook instance
/// is bound to exactly one guard (and hence one asset); pools holding two
/// guarded assets are outside this contract's scope. Reverting stops the swap
/// atomically inside the pool manager's callback, leaving pool balances
/// untouched. Fail-closed behavior depends on the guard implementation
/// reporting every uninitialized, halted, or stale state as disabled.
contract LULDGuardHook is BaseHook {
    /// @notice The guard contract consulted on every swap. Immutable so the
    /// checked asset cannot be swapped out from under existing pools.
    ITradingGuard public immutable guard;

    /// @notice A zero pool manager or guard address was supplied.
    error ZeroAddress();

    /// @notice The guard reports trading as disabled, so the swap is blocked.
    /// The guard address is immutable and readable on-chain, which is where
    /// operators trace the halt back to its source.
    error TradingHalted();

    /// @param _poolManager The v4 pool manager singleton this hook serves.
    /// @param _guard The single-asset guard answering for this hook's pools.
    constructor(IPoolManager _poolManager, ITradingGuard _guard) BaseHook(_poolManager) {
        if (address(_poolManager) == address(0) || address(_guard) == address(0)) revert ZeroAddress();
        guard = _guard;
    }

    /// @inheritdoc BaseHook
    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    /// @inheritdoc BaseHook
    function _beforeSwap(address, PoolKey calldata, SwapParams calldata, bytes calldata)
        internal
        view
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        if (!guard.tradingEnabled()) revert TradingHalted();
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }
}
