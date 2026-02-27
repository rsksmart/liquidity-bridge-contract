// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {HelperConfig} from "../../HelperConfig.s.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {LiquidityBridgeContractV2} from "../../../src/legacy/LiquidityBridgeContractV2.sol";
import {LiquidityBridgeContractAdmin} from "../../../src/legacy/LiquidityBridgeContractAdmin.sol";

/// @title ChangeOwnerToTimelock (Legacy)
/// @notice Deploys a TimelockController and transfers ownership of the LBC's
///         ProxyAdmin to it, gating contract upgrades behind a time delay.
/// @dev Only the ProxyAdmin is transferred to the timelock. The LBC contract
///      ownership is intentionally left unchanged so that time-sensitive operations
///      like emergency actions can be executed immediately.
contract ChangeOwnerToTimelock is Script {
    bytes32 internal constant ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    error ProxyAddressNotProvided();
    error TimelockProposerIsZero();
    error TimelockExecutorIsZero();
    error AdminAddressNotFound();
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

        vm.startBroadcast(deployerKey);
        TimelockController timelock = execute(proxyAddress, cfg);
        vm.stopBroadcast();

        _logFinalState(proxyAddress, timelock, cfg);
    }

    /// @notice Core logic: deploys a TimelockController and transfers the ProxyAdmin
    ///         ownership to it
    function execute(
        address proxyAddress,
        HelperConfig.NetworkConfig memory cfg
    ) public returns (TimelockController) {
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

        TimelockController timelock = new TimelockController(
            cfg.timelockMinDelay,
            proposers,
            executors,
            address(0)
        );

        _transferProxyAdminOwnership(proxyAddress, address(timelock));

        return timelock;
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
        if (admin.owner() == timelock) {
            return;
        }

        admin.transferOwnership(timelock);

        if (admin.owner() != timelock) {
            revert ProxyAdminOwnerTransferFailed();
        }
    }

    function _logFinalState(
        address proxyAddress,
        TimelockController timelock,
        HelperConfig.NetworkConfig memory cfg
    ) internal view {
        address adminAddress = address(
            uint160(uint256(vm.load(proxyAddress, ADMIN_SLOT)))
        );
        LiquidityBridgeContractAdmin admin = LiquidityBridgeContractAdmin(
            adminAddress
        );

        console.log("=== Timelock ownership setup complete ===");
        console.log("Timelock:", address(timelock));
        console.log("Timelock minDelay:", timelock.getMinDelay());
        console.log("ProxyAdmin owner:", admin.owner());
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
