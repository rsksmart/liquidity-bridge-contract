// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployFlyover} from "../../script/deployment/DeployFlyover.s.sol";
import {PegInContract} from "../../src/PegInContract.sol";

/// @title DeployFlyoverWiringTest
/// @notice Asserts deployForTesting wires PegInAddressRegistry and FlyoverConfigurations.
contract DeployFlyoverWiringTest is Test {
    function test_deployForTesting_wiresRegistryAndConfigurations() public {
        HelperConfig helper = new HelperConfig();
        HelperConfig.FlyoverConfig memory cfg = helper.getFlyoverConfig();
        DeployFlyover deployer = new DeployFlyover();

        DeployFlyover.FlyoverDeployment memory d = deployer.deployForTesting(
            address(deployer),
            cfg,
            helper.getOptions()
        );

        PegInContract pegIn = PegInContract(payable(d.pegInProxy));
        address registry = pegIn.getPegInAddressRegistry();
        address configurations = pegIn.getFlyoverConfigurations();

        assertTrue(registry != address(0), "PegInAddressRegistry should be set");
        assertTrue(
            configurations != address(0),
            "FlyoverConfigurations should be set"
        );
        assertEq(
            registry,
            d.pegInAddressRegistryProxy,
            "registry pointer mismatch"
        );
        assertEq(
            configurations,
            d.flyoverConfigurationsProxy,
            "configurations pointer mismatch"
        );
    }
}
