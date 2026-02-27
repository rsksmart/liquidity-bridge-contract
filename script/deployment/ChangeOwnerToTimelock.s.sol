// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/// @title ChangeOwnerToTimelock (Split Architecture)
/// @notice Deploys a TimelockController and transfers ownership of the shared
///         ProxyAdmin to it, gating contract upgrades behind a time delay.
/// @dev Only the ProxyAdmin is transferred to the timelock. The DEFAULT_ADMIN_ROLE
///      on individual contracts (CollateralManagement, PegIn, PegOut, FlyoverDiscovery)
///      is intentionally left unchanged so that time-sensitive operations like
///      emergency pause can be executed immediately.
contract ChangeOwnerToTimelock is Script {
    error TimelockProposerIsZero();
    error TimelockExecutorIsZero();
    error ProxyAdminAddressNotProvided();
    error ProxyAdminOwnerTransferFailed();

    function run() external {
        HelperConfig helper = new HelperConfig();
        HelperConfig.FlyoverConfig memory cfg = helper.getFlyoverConfig();
        uint256 deployerKey = helper.getDeployerPrivateKey();
        vm.rememberKey(deployerKey);

        address proxyAdminAddress = vm.envAddress("PROXY_ADMIN");
        if (proxyAdminAddress == address(0)) {
            revert ProxyAdminAddressNotProvided();
        }

        vm.startBroadcast(deployerKey);
        TimelockController timelock = execute(proxyAdminAddress, cfg);
        vm.stopBroadcast();

        _logFinalState(proxyAdminAddress, timelock, cfg);
    }

    /// @notice Core logic: deploys a TimelockController and transfers ProxyAdmin
    ///         ownership to it
    function execute(
        address proxyAdminAddress,
        HelperConfig.FlyoverConfig memory cfg
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

        ProxyAdmin admin = ProxyAdmin(proxyAdminAddress);
        if (admin.owner() != address(timelock)) {
            admin.transferOwnership(address(timelock));
            if (admin.owner() != address(timelock)) {
                revert ProxyAdminOwnerTransferFailed();
            }
        }

        return timelock;
    }

    function _logFinalState(
        address proxyAdminAddress,
        TimelockController timelock,
        HelperConfig.FlyoverConfig memory cfg
    ) internal view {
        console.log("=== Timelock ownership setup complete ===");
        console.log("Timelock:", address(timelock));
        console.log("Timelock minDelay:", timelock.getMinDelay());
        console.log(
            "Proposer role granted:",
            timelock.hasRole(timelock.PROPOSER_ROLE(), cfg.timelockProposer)
        );
        console.log(
            "Executor role granted:",
            timelock.hasRole(timelock.EXECUTOR_ROLE(), cfg.timelockExecutor)
        );
        console.log("ProxyAdmin:", proxyAdminAddress);
        console.log("ProxyAdmin owner:", ProxyAdmin(proxyAdminAddress).owner());
    }
}
