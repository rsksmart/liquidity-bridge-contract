// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployFlyover} from "../../script/deployment/DeployFlyover.s.sol";
import {FlyoverConfigurations} from "../../src/FlyoverConfigurations.sol";
import {FlyoverConfigurationsRegtest} from "../../src/libraries/FlyoverConfigurationsRegtest.sol";
import {PegInAddressRegistry} from "../../src/PegInAddressRegistry.sol";
import {PegInContract} from "../../src/PegInContract.sol";
import {PegOutEscrow} from "../../src/PegOutEscrow.sol";

/// @title DeployFlyoverWiringTest
/// @notice Asserts DeployFlyover wires PegInAddressRegistry and FlyoverConfigurations.
contract DeployFlyoverWiringTest is Test {
    // Anvil account 0. Used when DEV_SIGNER_PRIVATE_KEY is not in the environment.
    string internal constant TEST_SIGNER_KEY =
        "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";

    function test_run_wiresRegistryAndConfigurations() public {
        if (vm.envOr("DEV_SIGNER_PRIVATE_KEY", uint256(0)) == 0) {
            vm.setEnv("DEV_SIGNER_PRIVATE_KEY", TEST_SIGNER_KEY);
        }
        DeployFlyover.FlyoverDeployment memory d = new DeployFlyover().run();

        _assertWired(d);
    }

    function test_deployForTesting_wiresRegistryAndConfigurations() public {
        HelperConfig helper = new HelperConfig();
        HelperConfig.FlyoverConfig memory cfg = helper.getFlyoverConfig();
        DeployFlyover deployer = new DeployFlyover();

        DeployFlyover.FlyoverDeployment memory d = deployer.deployForTesting(
            address(deployer),
            cfg,
            helper.getOptions()
        );

        _assertWired(d);
    }

    function _assertWired(
        DeployFlyover.FlyoverDeployment memory d
    ) private view {
        PegInContract pegIn = PegInContract(payable(d.pegInProxy));
        assertTrue(
            d.pegInAddressRegistryProxy != address(0),
            "PegInAddressRegistry should be set"
        );
        assertTrue(
            d.flyoverConfigurationsProxy != address(0),
            "FlyoverConfigurations should be set"
        );
        assertEq(
            pegIn.getPegInAddressRegistry(),
            d.pegInAddressRegistryProxy,
            "registry pointer mismatch"
        );
        assertEq(
            pegIn.getFlyoverConfigurations(),
            d.flyoverConfigurationsProxy,
            "configurations pointer mismatch"
        );
        assertEq(
            address(
                PegInAddressRegistry(payable(d.pegInAddressRegistryProxy))
                    .getFlyoverConfigurations()
            ),
            d.flyoverConfigurationsProxy,
            "registry configurations pointer mismatch"
        );
        assertEq(
            PegOutEscrow(payable(d.pegOutEscrowProxy))
                .getFlyoverConfigurations(),
            d.flyoverConfigurationsProxy,
            "escrow configurations pointer mismatch"
        );
        assertEq(
            FlyoverConfigurations(payable(d.flyoverConfigurationsProxy))
                .getPegInConfiguration()
                .minAmount,
            FlyoverConfigurationsRegtest.pegInConfig().minAmount,
            "peg-in minAmount floor not seeded"
        );
    }
}
