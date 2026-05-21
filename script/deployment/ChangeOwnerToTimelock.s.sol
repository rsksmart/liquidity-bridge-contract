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
///      Proposers and executors are read from timelock-roles.json, falling back
///      to the single-address config values if the file is not available.
contract ChangeOwnerToTimelock is Script {
    error NoProposersConfigured();
    error NoExecutorsConfigured();
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

        (address[] memory proposers, address[] memory executors) = _readRoles(
            cfg
        );

        vm.startBroadcast(deployerKey);
        TimelockController timelock = execute(
            proxyAdminAddress,
            cfg.timelockMinDelay,
            proposers,
            executors,
            cfg.timelockAdmin
        );
        vm.stopBroadcast();

        _logFinalState(proxyAdminAddress, timelock, proposers, executors);
    }

    /// @notice Core logic: deploys a TimelockController and transfers ProxyAdmin
    ///         ownership to it. No console.log calls -- safe for broadcast.
    function execute(
        address proxyAdminAddress,
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) public returns (TimelockController) {
        if (proposers.length == 0) {
            revert NoProposersConfigured();
        }
        if (executors.length == 0) {
            revert NoExecutorsConfigured();
        }

        TimelockController timelock = new TimelockController(
            minDelay,
            proposers,
            executors,
            admin
        );

        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdminAddress);
        if (proxyAdmin.owner() != address(timelock)) {
            proxyAdmin.transferOwnership(address(timelock));
            if (proxyAdmin.owner() != address(timelock)) {
                revert ProxyAdminOwnerTransferFailed();
            }
        }

        return timelock;
    }

    function _readRoles(
        HelperConfig.FlyoverConfig memory cfg
    )
        internal
        view
        returns (address[] memory proposers, address[] memory executors)
    {
        string memory json = vm.readFile(
            "script/deployment/timelock-roles.json"
        );
        string memory networkKey = _networkKey();

        proposers = vm.parseJsonAddressArray(
            json,
            string.concat(".", networkKey, ".proposers")
        );
        executors = vm.parseJsonAddressArray(
            json,
            string.concat(".", networkKey, ".executors")
        );

        if (proposers.length == 0 && cfg.timelockProposer != address(0)) {
            proposers = new address[](1);
            proposers[0] = cfg.timelockProposer;
        }
        if (executors.length == 0 && cfg.timelockExecutor != address(0)) {
            executors = new address[](1);
            executors[0] = cfg.timelockExecutor;
        }
    }

    function _networkKey() internal view returns (string memory) {
        uint256 chainId = block.chainid;
        if (chainId == 30) return "rskMainnet";
        if (chainId == 31) return "rskTestnet";
        return "rskRegtest";
    }

    function _logFinalState(
        address proxyAdminAddress,
        TimelockController timelock,
        address[] memory proposers,
        address[] memory executors
    ) internal view {
        console.log("=== Timelock ownership setup complete ===");
        console.log("Timelock:", address(timelock));
        console.log("Timelock minDelay:", timelock.getMinDelay());
        console.log("ProxyAdmin:", proxyAdminAddress);
        console.log("ProxyAdmin owner:", ProxyAdmin(proxyAdminAddress).owner());

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        for (uint256 i = 0; i < proposers.length; i++) {
            console.log(
                "Proposer:",
                proposers[i],
                timelock.hasRole(proposerRole, proposers[i])
            );
        }
        for (uint256 i = 0; i < executors.length; i++) {
            console.log(
                "Executor:",
                executors[i],
                timelock.hasRole(executorRole, executors[i])
            );
        }
    }
}
