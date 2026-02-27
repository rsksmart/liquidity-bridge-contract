// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";

/// @title ChangeOwnerToTimelock (Split Architecture)
/// @notice Deploys a TimelockController and transfers ownership of all Flyover
///         contracts and their shared ProxyAdmin to it.
/// @dev The split architecture contracts use AccessControlDefaultAdminRulesUpgradeable,
///      which requires a two-step admin transfer:
///        1. This script calls beginDefaultAdminTransfer(timelock) on each contract.
///        2. The timelock must later call acceptDefaultAdminTransfer() on each contract
///           (scheduled via the proposer/executor after timelockMinDelay elapses).
///      ProxyAdmin uses standard Ownable and is transferred in a single step.
contract ChangeOwnerToTimelock is Script {
    struct ProxyAddresses {
        address collateralManagement;
        address flyoverDiscovery;
        address pegIn;
        address pegOut;
        address proxyAdmin;
    }

    error ProxyAddressNotProvided(string name);
    error TimelockProposerIsZero();
    error TimelockExecutorIsZero();
    error ProxyAdminAddressNotProvided();
    error ProxyAdminOwnerTransferFailed();

    function run() external {
        HelperConfig helper = new HelperConfig();
        HelperConfig.FlyoverConfig memory cfg = helper.getFlyoverConfig();
        uint256 deployerKey = helper.getDeployerPrivateKey();
        vm.rememberKey(deployerKey);

        ProxyAddresses memory proxies = _readProxyAddresses();

        vm.startBroadcast(deployerKey);
        TimelockController timelock = execute(proxies, cfg);
        vm.stopBroadcast();

        _logFinalState(proxies, timelock, cfg);
    }

    /// @notice Core logic: deploys a TimelockController and initiates ownership
    ///         transfers on all contracts. No console.log calls -- safe for broadcast.
    function execute(
        ProxyAddresses memory proxies,
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

        _beginAdminTransfer(proxies.collateralManagement, address(timelock));
        _beginAdminTransfer(proxies.flyoverDiscovery, address(timelock));
        _beginAdminTransfer(proxies.pegIn, address(timelock));
        _beginAdminTransfer(proxies.pegOut, address(timelock));

        _transferProxyAdminOwnership(proxies.proxyAdmin, address(timelock));

        return timelock;
    }

    function _readProxyAddresses()
        internal
        view
        returns (ProxyAddresses memory proxies)
    {
        proxies.collateralManagement = vm.envAddress(
            "COLLATERAL_MANAGEMENT_PROXY"
        );
        if (proxies.collateralManagement == address(0)) {
            revert ProxyAddressNotProvided("COLLATERAL_MANAGEMENT_PROXY");
        }

        proxies.flyoverDiscovery = vm.envAddress("FLYOVER_DISCOVERY_PROXY");
        if (proxies.flyoverDiscovery == address(0)) {
            revert ProxyAddressNotProvided("FLYOVER_DISCOVERY_PROXY");
        }

        proxies.pegIn = vm.envAddress("PEGIN_PROXY");
        if (proxies.pegIn == address(0)) {
            revert ProxyAddressNotProvided("PEGIN_PROXY");
        }

        proxies.pegOut = vm.envAddress("PEGOUT_PROXY");
        if (proxies.pegOut == address(0)) {
            revert ProxyAddressNotProvided("PEGOUT_PROXY");
        }

        proxies.proxyAdmin = vm.envAddress("PROXY_ADMIN");
        if (proxies.proxyAdmin == address(0)) {
            revert ProxyAdminAddressNotProvided();
        }
    }

    function _beginAdminTransfer(address proxy, address timelock) internal {
        AccessControlDefaultAdminRulesUpgradeable contract_ = AccessControlDefaultAdminRulesUpgradeable(
                proxy
            );

        if (contract_.defaultAdmin() == timelock) {
            return;
        }

        contract_.beginDefaultAdminTransfer(timelock);
    }

    function _transferProxyAdminOwnership(
        address proxyAdminAddress,
        address timelock
    ) internal {
        ProxyAdmin admin = ProxyAdmin(proxyAdminAddress);

        if (admin.owner() == timelock) {
            return;
        }

        admin.transferOwnership(timelock);

        if (admin.owner() != timelock) {
            revert ProxyAdminOwnerTransferFailed();
        }
    }

    function _logFinalState(
        ProxyAddresses memory proxies,
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

        console.log("--- ProxyAdmin ---");
        console.log("ProxyAdmin:", proxies.proxyAdmin);
        console.log(
            "ProxyAdmin owner:",
            ProxyAdmin(proxies.proxyAdmin).owner()
        );

        _logPendingTransfer(
            proxies.collateralManagement,
            "CollateralManagement"
        );
        _logPendingTransfer(proxies.flyoverDiscovery, "FlyoverDiscovery");
        _logPendingTransfer(proxies.pegIn, "PegIn");
        _logPendingTransfer(proxies.pegOut, "PegOut");

        console.log("=== ACTION REQUIRED ===");
        console.log(
            "The DEFAULT_ADMIN_ROLE transfers have been initiated but not yet accepted."
        );
        console.log(
            "The timelock must call acceptDefaultAdminTransfer() on each contract."
        );
        console.log(
            "Schedule these calls through the timelock proposer after the admin delay elapses."
        );
    }

    function _logPendingTransfer(
        address proxy,
        string memory name
    ) internal view {
        AccessControlDefaultAdminRulesUpgradeable contract_ = AccessControlDefaultAdminRulesUpgradeable(
                proxy
            );

        address currentAdmin = contract_.defaultAdmin();
        (address pendingAdmin, uint48 schedule) = contract_
            .pendingDefaultAdmin();

        console.log(string.concat("--- ", name, " ---"));
        console.log("Current admin:", currentAdmin);
        console.log("Pending admin:", pendingAdmin);
        console.log("Accept schedule:", uint256(schedule));
    }
}
