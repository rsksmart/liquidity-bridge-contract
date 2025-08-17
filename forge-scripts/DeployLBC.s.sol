// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "forge-std/Script.sol";

import {HelperConfig} from "./HelperConfig.s.sol";

import {LiquidityBridgeContract} from "../contracts/legacy/LiquidityBridgeContract.sol";
import {LiquidityBridgeContractProxy} from "../contracts/legacy/LiquidityBridgeContractProxy.sol";
import {LiquidityBridgeContractAdmin} from "../contracts/legacy/LiquidityBridgeContractAdmin.sol";

contract DeployLBC is Script {
    function run() external {
        HelperConfig helper = new HelperConfig();
        HelperConfig.NetworkConfig memory cfg = helper.getConfig();

        uint256 deployerKey = helper.getDeployerPrivateKey();
        address deployer = vm.rememberKey(deployerKey);

        vm.startBroadcast(deployerKey);

        // 1) Deploy implementation
        LiquidityBridgeContract implementation = new LiquidityBridgeContract();
        console.log("LiquidityBridgeContract implementation:", address(implementation));

        // 2) Deploy Proxy Admin (owner set to msg.sender inside the contract)
        LiquidityBridgeContractAdmin admin = new LiquidityBridgeContractAdmin();
        console.log("LiquidityBridgeContractAdmin:", address(admin));

        // 3) Prepare initializer calldata
        bytes memory initData = abi.encodeCall(
            LiquidityBridgeContract.initialize,
            (
                payable(cfg.bridge),
                cfg.minimumCollateral,
                cfg.minimumPegIn,
                cfg.rewardPercentage,
                cfg.resignDelayBlocks,
                cfg.dustThreshold,
                cfg.btcBlockTime,
                cfg.mainnet
            )
        );

        // 4) Deploy TransparentUpgradeableProxy with initializer
        LiquidityBridgeContractProxy proxy = new LiquidityBridgeContractProxy(
            address(implementation),
            address(admin),
            initData
        );
        console.log("LiquidityBridgeContract proxy:", address(proxy));

        // Optional: cast proxy to implementation ABI and read a value to sanity check
        LiquidityBridgeContract lbc = LiquidityBridgeContract(payable(address(proxy)));
        console.log("Bridge set to:", lbc.getBridgeAddress());

        vm.stopBroadcast();
    }
}
