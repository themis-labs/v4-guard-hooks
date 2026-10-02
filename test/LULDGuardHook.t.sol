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
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

import {LULDGuardHook} from "../src/LULDGuardHook.sol";
import {ITradingGuard} from "../src/interfaces/ITradingGuard.sol";

/// @notice Configurable stand-in for a production guard such as TSVGuard.
contract MockTradingGuard is ITradingGuard {
    bool private enabled;

    constructor(bool _enabled) {
        enabled = _enabled;
    }

    function setTradingEnabled(bool _enabled) external {
        enabled = _enabled;
    }

    function tradingEnabled() external view override returns (bool) {
        return enabled;
    }
}

/// @notice Coverage for the thin halt interceptor.
///
/// Deployment note: the hook is etched at a flag-compliant address with
/// forge-std's `deployCodeTo`, the same pattern the reference hook suites
/// use. Etching runs the real creation code at the target address, so the
/// base contract's address check executes exactly as in production; a
/// CREATE2 salt search would prove the same property at far higher fixture
/// cost. A mock pool manager address is enough here because the hook never
/// calls into the manager — the only interaction under test is the
/// manager-identity check on callbacks. A full pool fixture would add weight
/// without covering any extra hook behavior.
contract LULDGuardHookTest is Test {
    /// @dev Carries exactly the before-swap permission bit; high bits keep it
    /// clear of precompile addresses.
    address internal hookAddress = address(uint160(Hooks.BEFORE_SWAP_FLAG) ^ (0x4444 << 144));

    address internal poolManager = makeAddr("poolManager");
    MockTradingGuard internal guard;
    LULDGuardHook internal hook;

    function setUp() public {
        guard = new MockTradingGuard(true);
        deployCodeTo("LULDGuardHook.sol:LULDGuardHook", abi.encode(poolManager, address(guard)), hookAddress);
        hook = LULDGuardHook(hookAddress);
    }

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

    function test_Constructor_RevertsOnZeroPoolManager() public {
        // deployCodeTo wraps creation failures in its own message, so the
        // test drives etch plus a raw call to observe the custom error.
        bytes memory creationCode =
            abi.encodePacked(vm.getCode("LULDGuardHook.sol:LULDGuardHook"), abi.encode(address(0), address(guard)));
        vm.etch(hookAddress, creationCode);

        (bool ok, bytes memory ret) = hookAddress.call("");

        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(LULDGuardHook.ZeroAddress.selector));
    }

    function test_Constructor_RevertsOnZeroGuard() public {
        bytes memory creationCode =
            abi.encodePacked(vm.getCode("LULDGuardHook.sol:LULDGuardHook"), abi.encode(poolManager, address(0)));
        vm.etch(hookAddress, creationCode);

        (bool ok, bytes memory ret) = hookAddress.call("");

        assertFalse(ok);
        assertEq(ret, abi.encodeWithSelector(LULDGuardHook.ZeroAddress.selector));
    }

    function test_BeforeSwap_PassesThroughWhenTradingEnabled() public {
        guard.setTradingEnabled(true);

        vm.prank(poolManager);
        (bytes4 selector, BeforeSwapDelta delta, uint24 fee) = hook.beforeSwap(address(this), _key(), _swapParams(), "");

        assertTrue(selector == BaseHook.beforeSwap.selector);
        assertTrue(BeforeSwapDelta.unwrap(delta) == BeforeSwapDelta.unwrap(BeforeSwapDeltaLibrary.ZERO_DELTA));
        assertEq(fee, 0);
    }

    function test_BeforeSwap_RevertsWhenTradingHalted() public {
        guard.setTradingEnabled(false);

        vm.expectRevert(LULDGuardHook.TradingHalted.selector);
        vm.prank(poolManager);
        hook.beforeSwap(address(this), _key(), _swapParams(), "");
    }

    function test_BeforeSwap_RevertsForNonPoolManagerCaller() public {
        guard.setTradingEnabled(true);

        vm.expectRevert(BaseHook.NotPoolManager.selector);
        vm.prank(makeAddr("stranger"));
        hook.beforeSwap(address(this), _key(), _swapParams(), "");
    }

    function test_HookAddress_CarriesOnlyBeforeSwapFlag() public view {
        uint160 hookBits = uint160(address(hook));

        assertTrue((hookBits & Hooks.BEFORE_SWAP_FLAG) != 0);
        assertEq(hookBits & Hooks.ALL_HOOK_MASK, Hooks.BEFORE_SWAP_FLAG);
    }

    /// @dev PoolKey stores currencies as packed address values, so zeroed
    /// fields are sufficient input for a hook that never reads the key.
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
