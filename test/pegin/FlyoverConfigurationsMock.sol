// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";

/// @title FlyoverConfigurationsMock
/// @notice Test-only implementation of IFlyoverConfigurations with direct setters that bypass
/// the time-locked queue/apply flow, so tests can mutate fee, tiers, and bounds instantly.
/// @dev queueChange/applyChange are pass-through (queue stores, apply copies immediately); the
/// timelock is not modeled. Fee is fixedFee + amount * percentageFee / 10000.
/* solhint-disable comprehensive-interface */
contract FlyoverConfigurationsMock is IFlyoverConfigurations {
    uint256 private constant _BASIS_POINTS = 10000;

    PegConfiguration private _config;
    PegConfiguration private _queued;

    /// @notice Sets the fixed and percentage fee components directly
    function setFee(uint256 fixedFee, uint256 percentageFee) external {
        _config.fixedFee = fixedFee;
        _config.percentageFee = percentageFee;
    }

    /// @notice Sets the registrant fee directly
    function setRegistrantFee(uint256 registrantFee) external {
        _config.registrantFee = registrantFee;
    }

    /// @notice Sets the amount bounds directly
    function setAmountBounds(uint256 minAmount, uint256 maxAmount) external {
        _config.minAmount = minAmount;
        _config.maxAmount = maxAmount;
    }

    /// @notice Replaces the confirmation tiers directly
    function setConfirmationTiers(ConfirmationTier[] calldata tiers) external {
        delete _config.confirmationTiers;
        for (uint256 i = 0; i < tiers.length; i++) {
            _config.confirmationTiers.push(tiers[i]);
        }
    }

    /// @inheritdoc IFlyoverConfigurations
    function getPegInConfiguration()
        external
        view
        override
        returns (PegConfiguration memory configuration)
    {
        return _config;
    }

    /// @inheritdoc IFlyoverConfigurations
    function calculatePegInFee(
        uint256 amount
    ) external view override returns (uint256 fee) {
        return
            _config.fixedFee + (amount * _config.percentageFee) / _BASIS_POINTS;
    }

    /// @inheritdoc IFlyoverConfigurations
    function getRequiredPegInBtcConfirmations(
        uint256 amount
    ) external view override returns (uint256 confirmations) {
        uint256 tierCount = _config.confirmationTiers.length;
        for (uint256 i = 0; i < tierCount; i++) {
            if (amount <= _config.confirmationTiers[i].maxAmount) {
                return _config.confirmationTiers[i].confirmations;
            }
        }
        if (tierCount > 0) {
            return _config.confirmationTiers[tierCount - 1].confirmations;
        }
        return 0;
    }

    /// @inheritdoc IFlyoverConfigurations
    function queueChange(
        PegConfiguration calldata newConfiguration
    ) external override {
        _queued = newConfiguration;
    }

    /// @inheritdoc IFlyoverConfigurations
    function applyChange() external override {
        _config = _queued;
    }
}
/* solhint-enable comprehensive-interface */
