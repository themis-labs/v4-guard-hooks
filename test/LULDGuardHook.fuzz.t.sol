// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

import {LULDGuardHook} from "../src/LULDGuardHook.sol";
import {ITradingGuard} from "../src/interfaces/ITradingGuard.sol";

/// @notice Guard with a flippable switch for the fuzz and invariant suites.
/// Named apart from the unit suite's mock so both files compile together.
contract ToggleGuard is ITradingGuard {
    bool private enabled;

    function setEnabled(bool _enabled) external {
        enabled = _enabled;
    }

    function tradingEnabled() external view override returns (bool) {
        return enabled;
    }
}

/// @notice Proposition under test: the hook's pass/block decision depends
/// only on the guard's state at call time. Swap shapes, currency pairs,
/// fees, and caller-supplied sender fields move nothing; the hook keeps no
/// memory of past halts either.
contract LULDGuardHookFuzzTest is Test {
    /// @dev Carries exactly the before-swap permission bit, same shape as
    /// the unit suite's address.
    address internal hookAddress = address(uint160(Hooks.BEFORE_SWAP_FLAG) ^ (0x4444 << 144));

    address internal poolManager = makeAddr("poolManager");
    ToggleGuard internal guard;
    LULDGuardHook internal hook;

    bytes internal passBytes;
    bytes internal haltBytes;
    bytes internal strangerBytes;

    function setUp() public {
        guard = new ToggleGuard();
        deployCodeTo("LULDGuardHook.sol:LULDGuardHook", abi.encode(poolManager, address(guard)), hookAddress);
        hook = LULDGuardHook(hookAddress);

        passBytes = abi.encode(BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, uint24(0));
        haltBytes = abi.encodeWithSelector(LULDGuardHook.TradingHalted.selector);
        strangerBytes = abi.encodeWithSelector(BaseHook.NotPoolManager.selector);
    }

    /// @notice Matrix 1a: the swap shape varies freely (full int256
    /// amounts, any price limit, both directions, any sender field and
    /// hook data) while the key stays fixed, and the outcome is still
    /// fully determined by the guard state.
    function testFuzz_BeforeSwap_DecisionIgnoresSwapShape(
        bool enabled,
        address sender,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata hookData
    ) public {
        guard.setEnabled(enabled);
        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne, amountSpecified: amountSpecified, sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        vm.prank(poolManager);
        (bool ok, bytes memory ret) =
            hookAddress.call(abi.encodeCall(BaseHook.beforeSwap, (sender, _key(), params, hookData)));

        assertEq(ok, enabled);
        assertEq(ret, enabled ? passBytes : haltBytes);
    }

    /// @notice Matrix 1b: the pool key varies freely (any currency pair,
    /// fee, tick spacing, hooks field) while the swap stays fixed, with
    /// the same guard-determined outcome.
    function testFuzz_BeforeSwap_DecisionIgnoresKeyShape(
        bool enabled,
        address currencyA,
        address currencyB,
        uint24 fee,
        int24 tickSpacing,
        address keyHooks
    ) public {
        guard.setEnabled(enabled);
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(currencyA),
            currency1: Currency.wrap(currencyB),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(keyHooks)
        });

        vm.prank(poolManager);
        (bool ok, bytes memory ret) =
            hookAddress.call(abi.encodeCall(BaseHook.beforeSwap, (address(this), key, _swapParams(), "")));

        assertEq(ok, enabled);
        assertEq(ret, enabled ? passBytes : haltBytes);
    }

    /// @notice Matrix 2: any caller other than the pool manager is rejected
    /// before guard state is even consulted.
    function testFuzz_BeforeSwap_RejectsNonPoolManager(address caller, bool enabled) public {
        vm.assume(caller != poolManager);
        guard.setEnabled(enabled);

        vm.prank(caller);
        (bool ok, bytes memory ret) =
            hookAddress.call(abi.encodeCall(BaseHook.beforeSwap, (address(this), _key(), _swapParams(), "")));

        assertFalse(ok);
        assertEq(ret, strangerBytes);
    }

    /// @notice Matrix 2 positive control: the manager itself always reaches
    /// the guard check.
    function testFuzz_BeforeSwap_PoolManagerReachesGuard(bool enabled) public {
        guard.setEnabled(enabled);

        vm.prank(poolManager);
        (bool ok, bytes memory ret) =
            hookAddress.call(abi.encodeCall(BaseHook.beforeSwap, (address(this), _key(), _swapParams(), "")));

        assertEq(ok, enabled);
        assertEq(ret, enabled ? passBytes : haltBytes);
    }

    /// @notice Matrix 3a: any non-zero pair deploys with the guard readable
    /// back exactly as supplied.
    function testFuzz_Constructor_AcceptsNonZeroPair(address _poolManager, address _guard) public {
        vm.assume(_poolManager != address(0) && _guard != address(0));

        deployCodeTo("LULDGuardHook.sol:LULDGuardHook", abi.encode(_poolManager, _guard), hookAddress);

        assertEq(address(LULDGuardHook(hookAddress).guard()), _guard);
        assertEq(address(LULDGuardHook(hookAddress).poolManager()), _poolManager);
    }

    /// @notice Matrix 3b: a zero on either side reverts, whichever side it is.
    function testFuzz_Constructor_RejectsZeroAddress(bool zeroPoolManager, address other) public {
        vm.assume(other != address(0));

        bytes memory creationCode = abi.encodePacked(
            vm.getCode("LULDGuardHook.sol:LULDGuardHook"),
            zeroPoolManager ? abi.encode(address(0), other) : abi.encode(other, address(0))
        );
        vm.etch(hookAddress, creationCode);
        (bool ok, bytes memory ret) = hookAddress.call("");

        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(LULDGuardHook.ZeroAddress.selector));
    }

    /// @notice Matrix 5: permission declaration, pinned as a constant check
    /// next to the fuzzed behavior.
    function test_GetHookPermissions_OnlyBeforeSwap() public view {
        Hooks.Permissions memory permissions = hook.getHookPermissions();

        assertTrue(permissions.beforeSwap);
        assertFalse(permissions.beforeInitialize);
        assertFalse(permissions.afterInitialize);
        assertFalse(permissions.beforeAddLiquidity);
        assertFalse(permissions.afterAddLiquidity);
        assertFalse(permissions.beforeRemoveLiquidity);
        assertFalse(permissions.afterRemoveLiquidity);
        assertFalse(permissions.afterSwap);
        assertFalse(permissions.beforeDonate);
        assertFalse(permissions.afterDonate);
        assertFalse(permissions.beforeSwapReturnDelta);
        assertFalse(permissions.afterSwapReturnDelta);
        assertFalse(permissions.afterAddLiquidityReturnDelta);
        assertFalse(permissions.afterRemoveLiquidityReturnDelta);
    }

    function _key() internal pure returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(address(0)),
            fee: 0,
            tickSpacing: 0,
            hooks: IHooks(address(0))
        });
    }

    function _swapParams() internal pure returns (SwapParams memory) {
        return SwapParams({zeroForOne: true, amountSpecified: -1e18, sqrtPriceLimitX96: 0});
    }
}

/// @notice Driver for matrix 4: flips the guard and attempts swaps in an
/// order the fuzzer chooses. Every attempt records whether the outcome
/// matched the guard state read in the same call, so the invariant below
/// fails on the first divergence, including a latched halt.
contract LULDGuardHookSwapHandler is Test {
    ToggleGuard internal guard;
    LULDGuardHook internal hook;
    address internal poolManager;
    address internal hookAddress;

    uint256 public mismatches;

    constructor(address _guard, address _hook, address _poolManager) {
        guard = ToggleGuard(_guard);
        hook = LULDGuardHook(_hook);
        hookAddress = _hook;
        poolManager = _poolManager;
    }

    /// @dev Flips the guard; the next swap must track the new state, never
    /// the old one.
    function flip() external {
        guard.setEnabled(!guard.tradingEnabled());
    }

    /// @dev Attempts a swap shaped by the fuzzer and checks the outcome
    /// against the guard state read just before the call.
    function attemptSwap(bool zeroForOne, int256 amountSpecified, uint160 sqrtPriceLimitX96) external {
        bool expected = guard.tradingEnabled();
        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne, amountSpecified: amountSpecified, sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        vm.prank(poolManager);
        (bool ok,) = hookAddress.call(
            abi.encodeCall(
                BaseHook.beforeSwap,
                (
                    address(this),
                    PoolKey({
                        currency0: Currency.wrap(address(0)),
                        currency1: Currency.wrap(address(0)),
                        fee: 0,
                        tickSpacing: 0,
                        hooks: IHooks(address(0))
                    }),
                    params,
                    ""
                )
            )
        );

        if (ok != expected) ++mismatches;
    }
}

/// @notice Matrix 4: across arbitrary flip/swap interleavings, no recorded
/// swap ever disagrees with the guard state at its own call time.
contract LULDGuardHookInvariantTest is Test {
    LULDGuardHookSwapHandler internal handler;

    function setUp() public {
        address poolManager = makeAddr("poolManager");
        ToggleGuard guard = new ToggleGuard();
        address hookAddress = address(uint160(Hooks.BEFORE_SWAP_FLAG) ^ (0x4444 << 144));
        deployCodeTo("LULDGuardHook.sol:LULDGuardHook", abi.encode(poolManager, address(guard)), hookAddress);

        handler = new LULDGuardHookSwapHandler(address(guard), hookAddress, poolManager);
        targetContract(address(handler));
    }

    function invariant_SwapOutcomeAlwaysMatchesGuard() public view {
        assertEq(handler.mismatches(), 0);
    }
}
