// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {TestERC20} from "@uniswap/v4-core/src/test/TestERC20.sol";

/// @notice Demo constants shared by both scripts below.
library SepoliaDemoConfig {
    /// @dev Live hook deployed under 003.
    address internal constant HOOK = 0x3160E4eec2eaF776E0e3e4Ca0eB5931C350Bc080;
    /// @dev PoolManager singleton on Base Sepolia (chain id 84532).
    address internal constant POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;

    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;
    uint24 internal constant FEE = 3000;
    int24 internal constant TICK_SPACING = 60;
}

/// @notice Builds the demo pool: two test tokens, both routers, one
/// initialized pool carrying the live hook, one liquidity position.
///
/// @dev Demonstration scaffolding only: tokens and routers are throwaway
/// testnet fixtures, and every broadcasted call runs as the signing account,
/// so balances and approvals land on the broadcaster either way.
contract SeedSepoliaPool is Script {
    function run() external {
        vm.startBroadcast();
        TestERC20 tokenA = new TestERC20(1_000_000 ether);
        TestERC20 tokenB = new TestERC20(1_000_000 ether);
        PoolSwapTest swapRouter = new PoolSwapTest(IPoolManager(SepoliaDemoConfig.POOL_MANAGER));
        PoolModifyLiquidityTest liqRouter = new PoolModifyLiquidityTest(IPoolManager(SepoliaDemoConfig.POOL_MANAGER));

        tokenA.approve(address(swapRouter), type(uint256).max);
        tokenA.approve(address(liqRouter), type(uint256).max);
        tokenB.approve(address(swapRouter), type(uint256).max);
        tokenB.approve(address(liqRouter), type(uint256).max);

        (Currency currency0, Currency currency1) = address(tokenA) < address(tokenB)
            ? (Currency.wrap(address(tokenA)), Currency.wrap(address(tokenB)))
            : (Currency.wrap(address(tokenB)), Currency.wrap(address(tokenA)));
        PoolKey memory key = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: SepoliaDemoConfig.FEE,
            tickSpacing: SepoliaDemoConfig.TICK_SPACING,
            hooks: IHooks(SepoliaDemoConfig.HOOK)
        });
        IPoolManager(SepoliaDemoConfig.POOL_MANAGER).initialize(key, SepoliaDemoConfig.SQRT_PRICE_1_1);
        liqRouter.modifyLiquidity(
            key, ModifyLiquidityParams({tickLower: -600, tickUpper: 600, liquidityDelta: 100_000 ether, salt: 0}), ""
        );
        vm.stopBroadcast();

        console.log("token0:", Currency.unwrap(currency0));
        console.log("token1:", Currency.unwrap(currency1));
        console.log("swapRouter:", address(swapRouter));
        console.log("liqRouter:", address(liqRouter));
        console.log("poolId:");
        console.logBytes32(PoolId.unwrap(key.toId()));
    }
}

/// @notice Fires one demo swap against a seeded pool.
///
/// @dev Reads TOKEN0/TOKEN1/SWAP_ROUTER from the environment so fixture
/// addresses stay on the command line instead of in a file. The caller is
/// expected to hold the input token and to have approved the router, which
/// the seed script arranges for the broadcaster.
contract SwapSepoliaPool is Script {
    function run() external returns (int256 amount0, int256 amount1) {
        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(vm.envAddress("TOKEN0")),
            currency1: Currency.wrap(vm.envAddress("TOKEN1")),
            fee: SepoliaDemoConfig.FEE,
            tickSpacing: SepoliaDemoConfig.TICK_SPACING,
            hooks: IHooks(SepoliaDemoConfig.HOOK)
        });
        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: -1 ether, sqrtPriceLimitX96: 4295128740});
        PoolSwapTest.TestSettings memory settings =
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false});

        vm.startBroadcast();
        BalanceDelta delta = PoolSwapTest(vm.envAddress("SWAP_ROUTER")).swap(key, params, settings, "");
        vm.stopBroadcast();

        amount0 = delta.amount0();
        amount1 = delta.amount1();
        console.log("delta0:");
        console.logInt(amount0);
        console.log("delta1:");
        console.logInt(amount1);
    }
}
