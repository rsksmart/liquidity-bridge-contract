// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";

/// @title RegistryConfigurationsMock
/// @notice Stub that only serves {IFlyoverConfigurations-getPegInConfiguration} for registry tests.
contract RegistryConfigurationsMock {
    uint256 private _minAmount;

    function setMinAmount(uint256 minAmount) external {
        _minAmount = minAmount;
    }

    function getPegInConfiguration()
        external
        view
        returns (IFlyoverConfigurations.PegConfiguration memory configuration)
    {
        configuration.minAmount = _minAmount;
    }
}
