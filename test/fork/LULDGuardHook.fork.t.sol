// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {TestERC20} from "@uniswap/v4-core/src/test/TestERC20.sol";

import {LULDGuardHook} from "../../src/LULDGuardHook.sol";
import {ITradingGuard} from "../../src/interfaces/ITradingGuard.sol";

/// @notice Oracle-gated controls of the deployed guard, used only to drive
/// the fixture. The hook under test sees the guard through ITradingGuard
/// alone; these extra functions mirror the live deployment's relay surface.
interface IOracleControls {
    function tradingEnabled() external view returns (bool);
    function effectiveDailyVolume() external view returns (uint256);
    function maxDailyCap() external view returns (uint256);
    function hasRole(bytes32 role, address account) external view returns (bool);
    function setStockHaltStatus(bool isHalted) external;
    function recordVolume(uint256 addedVolume) external;
}

/// @notice End-to-end proof on a Base Sepolia fork: live PoolManager ->
/// freshly mined LULDGuardHook -> live guard. Each test re-forks, so oracle
/// pushes never leak between cases.
///
/// Oracle note: the deployed guard is plain AccessControl, which exposes no
/// member listing, so the oracle address is resolved at runtime from the
/// RoleGranted log in the guard's deployment block, then confirmed with a
/// hasRole read at fork state. Any later role change breaks loudly instead
/// of pranking a stale address. The deployment block is chain history used
/// as a scan bound, not an assumption: an empty scan reverts.
///
/// Mining note: the salt is searched in-test with this contract as the
/// deployer, which is exactly the address that executes CREATE2 below. The
/// 001 review lesson (mine against the broadcast signer) does not apply
/// here because no broadcast is involved.
///
/// Latest-block note: the fork tracks head without pinning, so tests 3 and
/// 6 read live guard state. A real halt or a filled cap on mainnet would
/// turn those cases red; that is the intended signal, not flakiness.
contract LULDGuardHookForkTest is Test {
    using StateLibrary for IPoolManager;

    /// @dev Live PoolManager singleton on Base Sepolia.
    address internal constant POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;
    /// @dev Live guard deployment under test.
    address internal constant GUARD = 0xBAcaF3d2765dcc314ee22CB19b87Cf755f5A6433;
    /// @dev First block carrying guard code, found by bisecting eth_getCode.
    uint256 internal constant GUARD_DEPLOY_BLOCK = 47187009;
    /// @dev Matches the guard's ORACLE_ROLE constant.
    bytes32 internal constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    /// @notice No single active oracle resolved from chain history.
    error OracleNotResolved();

    address internal oracle;
    LULDGuardHook internal hook;
    PoolKey internal key;
    PoolSwapTest internal swapRouter;
    PoolModifyLiquidityTest internal liqRouter;

    function setUp() public {
        vm.createSelectFork("base_sepolia");
        oracle = _findOracle();

        bytes memory creationCode = abi.encodePacked(type(LULDGuardHook).creationCode, abi.encode(POOL_MANAGER, GUARD));
        hook = new LULDGuardHook{salt: _mineSalt(creationCode)}(IPoolManager(POOL_MANAGER), ITradingGuard(GUARD));

        TestERC20 tokenA = new TestERC20(1_000_000 ether);
        TestERC20 tokenB = new TestERC20(1_000_000 ether);
        (Currency currency0, Currency currency1) = address(tokenA) < address(tokenB)
            ? (Currency.wrap(address(tokenA)), Currency.wrap(address(tokenB)))
            : (Currency.wrap(address(tokenB)), Currency.wrap(address(tokenA)));

        swapRouter = new PoolSwapTest(IPoolManager(POOL_MANAGER));
        liqRouter = new PoolModifyLiquidityTest(IPoolManager(POOL_MANAGER));
        tokenA.approve(address(swapRouter), type(uint256).max);
        tokenA.approve(address(liqRouter), type(uint256).max);
        tokenB.approve(address(swapRouter), type(uint256).max);
        tokenB.approve(address(liqRouter), type(uint256).max);

        key = PoolKey({
            currency0: currency0, currency1: currency1, fee: 3000, tickSpacing: 60, hooks: IHooks(address(hook))
        });
        IPoolManager(POOL_MANAGER).initialize(key, SQRT_PRICE_1_1);
        liqRouter.modifyLiquidity(
            key, ModifyLiquidityParams({tickLower: -600, tickUpper: 600, liquidityDelta: 100_000 ether, salt: 0}), ""
        );
    }

    /// @notice The mined hook address carries exactly the before-swap bit.
    function test_ForkHookAddress_CarriesOnlyBeforeSwapFlag() public view {
        uint160 hookBits = uint160(address(hook));

        assertTrue((hookBits & Hooks.BEFORE_SWAP_FLAG) != 0);
        assertEq(hookBits & Hooks.ALL_HOOK_MASK, Hooks.BEFORE_SWAP_FLAG);
    }

    /// @notice Liquidity calls pass straight through: the hook declares no
    /// liquidity permissions, so pool setup is unaffected by the guard.
    function test_InitializeAndAddLiquidity_PassThrough() public view {
        PoolId poolId = key.toId();
        (uint160 sqrtPriceX96,,,) = IPoolManager(POOL_MANAGER).getSlot0(poolId);
        assertEq(sqrtPriceX96, SQRT_PRICE_1_1);

        (uint128 liquidity,,) =
            IPoolManager(POOL_MANAGER).getPositionInfo(poolId, address(liqRouter), -600, 600, bytes32(0));
        assertTrue(liquidity > 0);
    }

    /// @notice A swap against the live guard state settles when trading is
    /// allowed.
    function test_Swap_SucceedsWhenGuardAllows() public {
        assertTrue(IOracleControls(GUARD).tradingEnabled());

        swapRouter.swap(key, _swapParams(), _testSettings(), "");

        assertGt(TestERC20(Currency.unwrap(key.currency1)).balanceOf(address(this)), 0);
    }

    /// @notice After the oracle reports a halt, the same swap reverts.
    /// @dev The hook's TradingHalted leaf is wrapped by the pool manager
    /// into WrappedError(hook, beforeSwap.selector, ...) on its way out
    /// through the router, so the assertion is any-revert: pinning the full
    /// tuple would hardcode the mined hook address. The leaf selector
    /// itself is pinned in the unit suite.
    function test_Swap_RevertsWhileHalted() public {
        vm.prank(oracle);
        IOracleControls(GUARD).setStockHaltStatus(true);
        assertFalse(IOracleControls(GUARD).tradingEnabled());

        vm.expectRevert();
        swapRouter.swap(key, _swapParams(), _testSettings(), "");
    }

    /// @notice Halting then resuming restores settlement: the hook tracks
    /// the guard instead of latching the halt.
    function test_Swap_SucceedsAfterResume() public {
        vm.prank(oracle);
        IOracleControls(GUARD).setStockHaltStatus(true);
        vm.prank(oracle);
        IOracleControls(GUARD).setStockHaltStatus(false);
        assertTrue(IOracleControls(GUARD).tradingEnabled());

        swapRouter.swap(key, _swapParams(), _testSettings(), "");

        assertGt(TestERC20(Currency.unwrap(key.currency1)).balanceOf(address(this)), 0);
    }

    /// @notice Pushing recorded volume past the daily cap disables trading
    /// through the same hook path as a halt.
    /// @dev Same revert-wrapping note as the halt case above.
    function test_Swap_RevertsWhenCapBreached() public {
        uint256 headroom = IOracleControls(GUARD).maxDailyCap() - IOracleControls(GUARD).effectiveDailyVolume();
        vm.prank(oracle);
        IOracleControls(GUARD).recordVolume(headroom + 1);
        assertFalse(IOracleControls(GUARD).tradingEnabled());

        vm.expectRevert();
        swapRouter.swap(key, _swapParams(), _testSettings(), "");
    }

    function _swapParams() internal pure returns (SwapParams memory) {
        return SwapParams({zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1});
    }

    function _testSettings() internal pure returns (PoolSwapTest.TestSettings memory) {
        return PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});
    }

    /// @dev Resolves the oracle from RoleGranted logs in the deployment
    /// block, minus revocations, confirmed against live membership. Reverts
    /// unless exactly one active oracle remains.
    function _findOracle() internal view returns (address) {
        bytes32[] memory grantTopics = new bytes32[](2);
        grantTopics[0] = keccak256("RoleGranted(bytes32,address,address)");
        grantTopics[1] = ORACLE_ROLE;
        Vm.EthGetLogs[] memory grants = vm.eth_getLogs(GUARD_DEPLOY_BLOCK, GUARD_DEPLOY_BLOCK, GUARD, grantTopics);

        bytes32[] memory revokeTopics = new bytes32[](2);
        revokeTopics[0] = keccak256("RoleRevoked(bytes32,address,address)");
        revokeTopics[1] = ORACLE_ROLE;
        Vm.EthGetLogs[] memory revokes = vm.eth_getLogs(GUARD_DEPLOY_BLOCK, GUARD_DEPLOY_BLOCK, GUARD, revokeTopics);

        address candidate = address(0);
        uint256 active = 0;
        for (uint256 i; i < grants.length; ++i) {
            address account = address(uint160(uint256(grants[i].topics[2])));
            if (!_revoked(revokes, account) && IOracleControls(GUARD).hasRole(ORACLE_ROLE, account)) {
                candidate = account;
                ++active;
            }
        }
        if (active != 1) revert OracleNotResolved();
        return candidate;
    }

    function _revoked(Vm.EthGetLogs[] memory revokes, address account) internal pure returns (bool) {
        for (uint256 i; i < revokes.length; ++i) {
            if (address(uint160(uint256(revokes[i].topics[2]))) == account) return true;
        }
        return false;
    }

    /// @dev Exact-mask search: every permission bit is fixed, so convergence
    /// takes on the order of sixteen thousand tries.
    function _mineSalt(bytes memory creationCode) internal view returns (bytes32) {
        for (uint256 i; i < 1_000_000; ++i) {
            bytes32 salt = bytes32(i);
            address candidate = address(
                uint160(
                    uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(creationCode))))
                )
            );
            if ((uint160(candidate) & Hooks.ALL_HOOK_MASK) == Hooks.BEFORE_SWAP_FLAG) return salt;
        }
        revert("salt search failed");
    }
}
