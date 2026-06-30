// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {HelperConfig} from "../HelperConfig.s.sol";
import {FlyoverConfigurations} from "../../src/FlyoverConfigurations.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/// @title DeployFlyoverConfigurations
/// @notice Deploys FlyoverConfigurations behind a transparent proxy, seeded with the provisional
/// PoC parameters from the S0.3 parameter set. All values are regtest placeholders, adjustable for
/// prod through the time-locked setters, bounded by the immutable deployment bounds set here.
contract DeployFlyoverConfigurations is Script {
    struct DeploymentResult {
        address implementation;
        address proxy;
        address admin;
    }

    function run() external returns (DeploymentResult memory result) {
        HelperConfig helper = new HelperConfig();
        HelperConfig.FlyoverConfig memory cfg = helper.getFlyoverConfig();
        uint256 deployerKey = helper.getDeployerPrivateKey();
        address deployer = vm.rememberKey(deployerKey);

        vm.startBroadcast(deployerKey);
        result = _deploy(deployer, cfg);
        vm.stopBroadcast();

        _log(result);
    }

    /// @notice Builds the provisional default configuration for one flow per the S0.3 parameters.
    /// @param cfg The network helper config (provides btcBlockTime for the delivery grace)
    function _defaultConfig(HelperConfig.FlyoverConfig memory cfg)
        private
        pure
        returns (IFlyoverConfigurations.PegConfiguration memory config)
    {
        // Provisional placeholders. fixedFee floor is a regtest placeholder; calibrate (>= 3x
        // worst-case gas) before prod per the fee-floor security gate.
        config.fixedFee = 0.0001 ether;
        config.percentageFee = 10;            // 0.1% on the 10_000 = 100% scale
        config.penaltyFee = 0.01 ether;       // individual slash
        config.callTime = 2 hours;            // LP action after claim
        config.expireTime = 2 hours + 30 minutes; // refund-enable, strictly later than callTime
        config.expireBlocks = 500;
        config.deliveryGrace = 2 * cfg.btcBlockTime; // 2x btcBlockTime
        config.minAmount = cfg.minimumPegIn;
        config.maxAmount = 100 ether;

        // Confirmation tiers: small -> 1, medium -> 3, large -> 6 (regtest-friendly low counts).
        config.confirmationTiers = new IFlyoverConfigurations.ConfirmationTier[](3);
        config.confirmationTiers[0] = IFlyoverConfigurations.ConfirmationTier({maxAmount: 1 ether, confirmations: 1});
        config.confirmationTiers[1] = IFlyoverConfigurations.ConfirmationTier({maxAmount: 10 ether, confirmations: 3});
        config.confirmationTiers[2] = IFlyoverConfigurations.ConfirmationTier({maxAmount: 100 ether, confirmations: 6});
    }

    /// @notice Wide deployment bounds: every default sits inside them, leaving room for time-locked
    /// adjustment without permitting unsafe extremes.
    function _bounds()
        private
        pure
        returns (
            IFlyoverConfigurations.PegConfiguration memory min,
            IFlyoverConfigurations.PegConfiguration memory max
        )
    {
        min.fixedFee = 0;
        min.percentageFee = 0;
        min.penaltyFee = 0;
        min.callTime = 1 minutes;
        min.expireTime = 1 minutes;
        min.expireBlocks = 1;
        min.deliveryGrace = 0;
        min.minAmount = 0;
        min.maxAmount = 0;

        max.fixedFee = 1 ether;
        max.percentageFee = 1_000;            // up to 10%
        max.penaltyFee = 10 ether;
        max.callTime = 7 days;
        max.expireTime = 8 days;
        max.expireBlocks = 1_000_000;
        max.deliveryGrace = 1 days;
        max.minAmount = 1 ether;
        max.maxAmount = 10_000 ether;
    }

    function _deploy(
        address defaultAdmin,
        HelperConfig.FlyoverConfig memory cfg
    ) private returns (DeploymentResult memory result) {
        IFlyoverConfigurations.PegConfiguration memory pegInConfig = _defaultConfig(cfg);
        IFlyoverConfigurations.PegConfiguration memory pegOutConfig = _defaultConfig(cfg);
        (
            IFlyoverConfigurations.PegConfiguration memory boundsMin,
            IFlyoverConfigurations.PegConfiguration memory boundsMax
        ) = _bounds();

        result.implementation = address(new FlyoverConfigurations());
        result.admin = address(new ProxyAdmin(defaultAdmin));
        result.proxy = address(
            new TransparentUpgradeableProxy(
                result.implementation,
                result.admin,
                abi.encodeCall(
                    FlyoverConfigurations.initialize,
                    (
                        defaultAdmin,
                        cfg.adminDelay,
                        cfg.timelockMinDelay,
                        pegInConfig,
                        pegOutConfig,
                        boundsMin,
                        boundsMax,
                        boundsMin,
                        boundsMax
                    )
                )
            )
        );
    }

    function _log(DeploymentResult memory r) private pure {
        console.log("=== FlyoverConfigurations Deployed ===");
        console.log("Implementation:", r.implementation);
        console.log("Proxy:", r.proxy);
        console.log("ProxyAdmin:", r.admin);
    }
}
