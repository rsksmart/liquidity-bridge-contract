// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {HelperConfig} from "../../HelperConfig.s.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {LiquidityBridgeContractAdmin} from "../../../src/legacy/LiquidityBridgeContractAdmin.sol";

/// @title ChangeOwnerToTimelock (Legacy)
/// @notice Deploys a TimelockController and transfers ownership of the LBC's
///         ProxyAdmin to it, gating contract upgrades behind a time delay.
/// @dev Only the ProxyAdmin is transferred to the timelock. The LBC contract
///      ownership is intentionally left unchanged so that time-sensitive operations
///      like emergency actions can be executed immediately.
///      Proposers and executors are read from timelock-roles.json, falling back
///      to the single-address config values if the file is not available.
contract ChangeOwnerToTimelock is Script {
    bytes32 internal constant ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    error ProxyAddressNotProvided();
    error NoProposersConfigured();
    error NoExecutorsConfigured();
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

        (address[] memory proposers, address[] memory executors) = _readRoles(
            cfg
        );

        vm.startBroadcast(deployerKey);
        TimelockController timelock = execute(
            proxyAddress,
            cfg.timelockMinDelay,
            proposers,
            executors,
            cfg.timelockAdmin
        );
        vm.stopBroadcast();

        _logFinalState(proxyAddress, timelock, proposers, executors);
    }

    /// @notice Core logic: deploys a TimelockController and transfers the ProxyAdmin
    ///         ownership to it. No console.log calls -- safe for broadcast.
    function execute(
        address proxyAddress,
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

    function _readRoles(
        HelperConfig.NetworkConfig memory cfg
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
        address proxyAddress,
        TimelockController timelock,
        address[] memory proposers,
        address[] memory executors
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
