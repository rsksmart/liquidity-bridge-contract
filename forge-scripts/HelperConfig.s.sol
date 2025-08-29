// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "forge-std/Script.sol";
import {BridgeMock} from "../contracts/test-contracts/BridgeMock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address bridge;
        uint256 minimumCollateral;
        uint256 minimumPegIn;
        uint32 rewardPercentage;
        uint32 resignDelayBlocks;
        uint256 dustThreshold;
        uint256 btcBlockTime;
        bool mainnet;
        address existingProxy;
        address existingAdmin;
    }

    NetworkConfig private cachedConfig;

    function getConfig() public returns (NetworkConfig memory) {
        if (cachedConfig.bridge != address(0)) {
            return cachedConfig;
        }

        uint256 chainId = block.chainid;

        if (chainId == 30) {
            cachedConfig = getMainnetConfig();
        } else if (chainId == 31) {
            cachedConfig = getTestnetConfig();
        } else {
            cachedConfig = getLocalConfig();
        }

        return cachedConfig;
    }

    function getDeployerPrivateKey() public view returns (uint256) {

        uint256 chainId = block.chainid;

        if (chainId == 30) {
            return vm.envUint("MAINNET_SIGNER_PRIVATE_KEY");
        } else if (chainId == 31) {
            return vm.envUint("TESTNET_SIGNER_PRIVATE_KEY");
        } else {
            return vm.envUint("DEV_SIGNER_PRIVATE_KEY");
        }
    }

    function getMainnetConfig() internal view returns (NetworkConfig memory) {
        // Must be provided via env
        address bridgeAddr = vm.envOr("BRIDGE_ADDRESS_MAINNET", address(0x0000000000000000000000000000000001000006));
        return NetworkConfig({
            bridge: bridgeAddr,
            minimumCollateral: vm.envOr("MIN_COLLATERAL_MAINNET", uint256(0.5 ether)),
            minimumPegIn: vm.envOr("MIN_PEGIN_MAINNET", uint256(0.01 ether)),
            rewardPercentage: uint32(vm.envOr("REWARD_P_MAINNET", uint256(50))),
            resignDelayBlocks: uint32(vm.envOr("RESIGN_BLOCKS_MAINNET", uint256(120))),
            dustThreshold: vm.envOr("DUST_THRESHOLD_MAINNET", uint256(10_000)),
            btcBlockTime: vm.envOr("BTC_BLOCK_TIME_MAINNET", uint256(600)),
            mainnet: true,
            existingProxy: vm.envOr("EXISTING_PROXY_MAINNET", address(0)),
            existingAdmin: vm.envOr("EXISTING_ADMIN_MAINNET", address(0))
        });
    }

    function getTestnetConfig() internal view returns (NetworkConfig memory) {
        // Must be provided via env
        address bridgeAddr = vm.envOr("BRIDGE_ADDRESS_TESTNET", address(0x0000000000000000000000000000000001000006));
        return NetworkConfig({
            bridge: bridgeAddr,
            minimumCollateral: vm.envOr("MIN_COLLATERAL_TESTNET", uint256(0.1 ether)),
            minimumPegIn: vm.envOr("MIN_PEGIN_TESTNET", uint256(0.005 ether)),
            rewardPercentage: uint32(vm.envOr("REWARD_P_TESTNET", uint256(50))),
            resignDelayBlocks: uint32(vm.envOr("RESIGN_BLOCKS_TESTNET", uint256(100))),
            dustThreshold: vm.envOr("DUST_THRESHOLD_TESTNET", uint256(10_000)),
            btcBlockTime: vm.envOr("BTC_BLOCK_TIME_TESTNET", uint256(600)),
            mainnet: false,
            existingProxy: vm.envOr("EXISTING_PROXY_TESTNET", address(0x3a23612AC7dD7fc7610A8898de11AE98E76BbC4F)),
            existingAdmin: vm.envOr("EXISTING_ADMIN_TESTNET", address(0x93891ACe405cC4F7b9974C22e34D6479eE6425e5))
        });
    }

    function getLocalConfig() internal returns (NetworkConfig memory) {
        // Deploy mock bridge locally
        BridgeMock bridge = new BridgeMock();

        return NetworkConfig({
            bridge: address(bridge),
            minimumCollateral: vm.envOr("MIN_COLLATERAL_LOCAL", uint256(0.05 ether)),
            minimumPegIn: vm.envOr("MIN_PEGIN_LOCAL", uint256(0.001 ether)),
            rewardPercentage: uint32(vm.envOr("REWARD_P_LOCAL", uint256(50))),
            resignDelayBlocks: uint32(vm.envOr("RESIGN_BLOCKS_LOCAL", uint256(80))),
            dustThreshold: vm.envOr("DUST_THRESHOLD_LOCAL", uint256(10_000)),
            btcBlockTime: vm.envOr("BTC_BLOCK_TIME_LOCAL", uint256(600)),
            mainnet: false,
            existingProxy: vm.envOr("EXISTING_PROXY_LOCAL", address(0)),
            existingAdmin: vm.envOr("EXISTING_ADMIN_LOCAL", address(0))
        });
    }
}
