// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {HelperConfig} from "../../HelperConfig.s.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {LiquidityBridgeContractV2} from "../../../src/legacy/LiquidityBridgeContractV2.sol";
import {LiquidityBridgeContractAdmin} from "../../../src/legacy/LiquidityBridgeContractAdmin.sol";

contract ChangeOwnerToTimelock is Script {
    bytes32 internal constant ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    error ProxyAddressNotProvided();
    error TimelockProposerIsZero();
    error TimelockExecutorIsZero();
    error OnlyCurrentLbcOwnerCanTransferOwnership();
    error ContractOwnerTransferFailed();
    error AdminAddressNotFound();
    error OnlyCurrentProxyAdminOwnerCanTransferOwnership();
    error ProxyAdminOwnerTransferFailed();

    function run() external {
        HelperConfig helper = new HelperConfig();
        HelperConfig.NetworkConfig memory cfg = helper.getConfig();

        uint256 deployerKey = helper.getDeployerPrivateKey();
        vm.rememberKey(deployerKey);

        address proxyAddress = cfg.existingProxy;
        if (proxyAddress == address(0)) {
            revert ProxyAddressNotProvided();
        }
        if (cfg.timelockProposer == address(0)) {
            revert TimelockProposerIsZero();
        }
        if (cfg.timelockExecutor == address(0)) {
            revert TimelockExecutorIsZero();
        }

        address[] memory proposers = new address[](1);
        proposers[0] = cfg.timelockProposer;

        address[] memory executors = new address[](1);
        executors[0] = cfg.timelockExecutor;

        vm.startBroadcast(deployerKey);

        TimelockController timelock = new TimelockController(
            cfg.timelockMinDelay,
            proposers,
            executors,
            address(0)
        );

        _transferContractOwnership(proxyAddress, address(timelock));
        _transferProxyAdminOwnership(proxyAddress, address(timelock));

        vm.stopBroadcast();

        _logFinalState(proxyAddress, timelock, cfg);
    }

    function _transferContractOwnership(
        address proxyAddress,
        address timelock
    ) internal {
        LiquidityBridgeContractV2 contract_ = LiquidityBridgeContractV2(
            payable(proxyAddress)
        );
        address currentOwner = contract_.owner();
        if (currentOwner != timelock) {
            if (currentOwner != msg.sender) {
                revert OnlyCurrentLbcOwnerCanTransferOwnership();
            }
            contract_.transferOwnership(timelock);
        }
        if (contract_.owner() != timelock) {
            revert ContractOwnerTransferFailed();
        }
    }

    function _transferProxyAdminOwnership(
        address proxyAddress,
        address timelock
    ) internal {
        address adminAddress = address(
            uint160(uint256(vm.load(proxyAddress, ADMIN_SLOT)))
        );
        if (adminAddress == address(0)) {
            revert AdminAddressNotFound();
        }

        LiquidityBridgeContractAdmin admin = LiquidityBridgeContractAdmin(
            adminAddress
        );
        address currentAdminOwner = admin.owner();
        if (currentAdminOwner != timelock) {
            if (currentAdminOwner != msg.sender) {
                revert OnlyCurrentProxyAdminOwnerCanTransferOwnership();
            }
            admin.transferOwnership(timelock);
        }
        if (admin.owner() != timelock) {
            revert ProxyAdminOwnerTransferFailed();
        }
    }

    function _logFinalState(
        address proxyAddress,
        TimelockController timelock,
        HelperConfig.NetworkConfig memory cfg
    ) internal view {
        LiquidityBridgeContractV2 contract_ = LiquidityBridgeContractV2(
            payable(proxyAddress)
        );
        address adminAddress = address(
            uint160(uint256(vm.load(proxyAddress, ADMIN_SLOT)))
        );
        LiquidityBridgeContractAdmin admin = LiquidityBridgeContractAdmin(
            adminAddress
        );

        console.log("=== Timelock ownership setup complete ===");
        console.log("Timelock:", address(timelock));
        console.log("Timelock minDelay:", timelock.getMinDelay());
        console.log("LBC owner:", contract_.owner());
        console.log("Expected timelock:", address(timelock));
        console.log("ProxyAdmin owner:", admin.owner());
        console.log("Expected timelock:", address(timelock));
        console.log(
            "Proposer role granted:",
            timelock.hasRole(timelock.PROPOSER_ROLE(), cfg.timelockProposer)
        );
        console.log(
            "Executor role granted:",
            timelock.hasRole(timelock.EXECUTOR_ROLE(), cfg.timelockExecutor)
        );
    }
}
