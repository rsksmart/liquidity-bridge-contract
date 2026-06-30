// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FlyoverConfigurations} from "../../src/FlyoverConfigurations.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";

/// @title ConfigurationsTestBase
/// @notice Shared setup for the FlyoverConfigurations suite: deploys behind an ERC1967 proxy with
/// a known seed config, generous bounds, and a non-zero time-lock delay.
abstract contract ConfigurationsTestBase is Test {
    uint48 internal constant ADMIN_DELAY = 0;
    uint256 internal constant TIMELOCK_DELAY = 1 days;
    uint256 internal constant SAT = 10 ** 10;

    address internal owner = address(0xA11CE);
    address internal stranger = address(0xBEEF);

    FlyoverConfigurations internal config;

    function _deploy() internal {
        FlyoverConfigurations impl = new FlyoverConfigurations();
        (
            IFlyoverConfigurations.PegConfiguration memory pegIn,
            IFlyoverConfigurations.PegConfiguration memory pegOut
        ) = _seedConfigs();
        (
            IFlyoverConfigurations.PegConfiguration memory min,
            IFlyoverConfigurations.PegConfiguration memory max
        ) = _bounds();

        bytes memory initData = abi.encodeCall(
            FlyoverConfigurations.initialize,
            (owner, ADMIN_DELAY, TIMELOCK_DELAY, pegIn, pegOut, min, max, min, max)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        config = FlyoverConfigurations(payable(address(proxy)));
    }

    /// @notice Peg-in and peg-out seeds differ (different fixedFee/percentageFee/tiers) so tests
    /// can prove the two flows read their own configuration.
    function _seedConfigs()
        internal
        pure
        returns (
            IFlyoverConfigurations.PegConfiguration memory pegIn,
            IFlyoverConfigurations.PegConfiguration memory pegOut
        )
    {
        pegIn = _baseConfig();
        pegIn.fixedFee = 1000 * SAT; // 1e13 wei, satoshi-aligned
        pegIn.percentageFee = 10;    // 0.1%
        pegIn.confirmationTiers = new IFlyoverConfigurations.ConfirmationTier[](3);
        pegIn.confirmationTiers[0] = IFlyoverConfigurations.ConfirmationTier({maxAmount: 1 ether, confirmations: 1});
        pegIn.confirmationTiers[1] = IFlyoverConfigurations.ConfirmationTier({maxAmount: 10 ether, confirmations: 3});
        pegIn.confirmationTiers[2] = IFlyoverConfigurations.ConfirmationTier({maxAmount: 100 ether, confirmations: 6});

        pegOut = _baseConfig();
        pegOut.fixedFee = 2000 * SAT; // distinct from peg-in
        pegOut.percentageFee = 20;    // 0.2%
        pegOut.confirmationTiers = new IFlyoverConfigurations.ConfirmationTier[](2);
        pegOut.confirmationTiers[0] = IFlyoverConfigurations.ConfirmationTier({maxAmount: 5 ether, confirmations: 2});
        pegOut.confirmationTiers[1] = IFlyoverConfigurations.ConfirmationTier({maxAmount: 50 ether, confirmations: 4});
    }

    function _baseConfig() internal pure returns (IFlyoverConfigurations.PegConfiguration memory c) {
        c.fixedFee = 1000 * SAT;
        c.percentageFee = 10;
        c.penaltyFee = 0.01 ether;
        c.callTime = 2 hours;
        c.expireTime = 2 hours + 30 minutes;
        c.expireBlocks = 500;
        c.deliveryGrace = 60;
        c.minAmount = 0.001 ether;
        c.maxAmount = 100 ether;
    }

    function _bounds()
        internal
        pure
        returns (
            IFlyoverConfigurations.PegConfiguration memory min,
            IFlyoverConfigurations.PegConfiguration memory max
        )
    {
        // min stays at all-zero struct defaults; wide max below.
        min.fixedFee = 0;
        max.fixedFee = 1 ether;
        max.percentageFee = 1_000;
        max.penaltyFee = 10 ether;
        max.callTime = 7 days;
        max.expireTime = 8 days;
        max.expireBlocks = 1_000_000;
        max.deliveryGrace = 1 days;
        max.minAmount = 1 ether;
        max.maxAmount = 10_000 ether;
    }
}
