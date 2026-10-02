// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {LULDGuardHook} from "../src/LULDGuardHook.sol";
import {ITradingGuard} from "../src/interfaces/ITradingGuard.sol";

/// @notice Minimal CREATE2 salt search for hook addresses.
///
/// @dev Uniswap v4 encodes hook permissions in the deployment address, so a
/// hook that declares `beforeSwap` must live at an address carrying that
/// permission bit. This helper iterates salts until the derived CREATE2
/// address carries exactly the wanted bits, then the caller deploys with the
/// winning salt. It follows the same search idea as the ecosystem's
/// hook-mining helpers, rewritten here so deployment tooling stays inside
/// this delivery. Mining and deployment must use the same deployer address;
/// this script performs both steps in one run, which keeps them consistent.
library HookMiner {
    /// @notice No salt produced the wanted address within the search bound.
    error SaltNotFound();

    /// @param deployer The contract that will execute the CREATE2 deployment.
    /// @param wanted The exact permission bits the hook address must carry.
    /// @param creationCode Creation code including the encoded constructor args.
    /// @return salt The first salt whose derived address matches `wanted`.
    function find(address deployer, uint160 wanted, bytes memory creationCode) internal pure returns (bytes32 salt) {
        for (uint256 i; i < 1_000_000; ++i) {
            salt = bytes32(i);
            if ((uint160(compute(deployer, salt, creationCode)) & Hooks.ALL_HOOK_MASK) == wanted) return salt;
        }
        revert SaltNotFound();
    }

    /// @dev EIP-1014 address derivation for a CREATE2 deployment.
    function compute(address deployer, bytes32 salt, bytes memory creationCode) internal pure returns (address) {
        return
            address(
                uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, keccak256(creationCode)))))
            );
    }
}

/// @notice Deploys one LULDGuardHook bound to a chosen guard on Base Sepolia.
///
/// @dev Delivery only: review the logged address and salt, then broadcast
/// separately against a funded signer. The guard address comes from the
/// `GUARD_ADDRESS` environment variable; the pool manager is the canonical
/// Base Sepolia singleton, so it is a constant here rather than an input.
contract DeployLULDGuardHook is Script {
    /// @dev PoolManager singleton on Base Sepolia (chain id 84532).
    address internal constant POOL_MANAGER = 0x05E73354cFDd6745C338b50BcFDfA3Aa6fA03408;

    function run() external returns (LULDGuardHook hook) {
        address guardAddress = vm.envAddress("GUARD_ADDRESS");
        if (guardAddress == address(0)) revert LULDGuardHook.ZeroAddress();

        bytes memory creationCode =
            abi.encodePacked(type(LULDGuardHook).creationCode, abi.encode(POOL_MANAGER, guardAddress));
        bytes32 salt = HookMiner.find(address(this), Hooks.BEFORE_SWAP_FLAG, creationCode);

        vm.startBroadcast();
        hook = new LULDGuardHook{salt: salt}(IPoolManager(POOL_MANAGER), ITradingGuard(guardAddress));
        vm.stopBroadcast();

        require((uint160(address(hook)) & Hooks.ALL_HOOK_MASK) == Hooks.BEFORE_SWAP_FLAG, "hook flag mismatch");

        console.log("LULDGuardHook deployed at:", address(hook));
        console.log("salt:");
        console.logBytes32(salt);
    }
}
