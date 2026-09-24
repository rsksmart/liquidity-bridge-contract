// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployFlyover} from "../../script/deployment/DeployFlyover.s.sol";
import {DeployFlyoverConfigurations} from "../../script/deployment/DeployFlyoverConfigurations.s.sol";
import {PegInContract} from "../../src/PegInContract.sol";

/// @title DeployFlyoverWiringTest
/// @notice Asserts deployForTesting wires PegInAddressRegistry and FlyoverConfigurations.
contract DeployFlyoverWiringTest is Test {
    // Anvil account 0. Only used so run() can resolve a signer after the live-network check.
    string internal constant TEST_SIGNER_KEY =
        "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";

    function test_run_revertsOnMainnetChainId() public {
        _runDeployFlyoverOnChain(30, "MAINNET_SIGNER_PRIVATE_KEY");
    }

    function test_run_revertsOnTestnetChainId() public {
        _runDeployFlyoverOnChain(31, "TESTNET_SIGNER_PRIVATE_KEY");
    }

    function test_deployFlyoverConfigurations_run_revertsOnMainnetChainId()
        public
    {
        _runDeployFlyoverConfigurationsOnChain(30, "MAINNET_SIGNER_PRIVATE_KEY");
    }

    function test_deployFlyoverConfigurations_run_revertsOnTestnetChainId()
        public
    {
        _runDeployFlyoverConfigurationsOnChain(31, "TESTNET_SIGNER_PRIVATE_KEY");
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

        PegInContract pegIn = PegInContract(payable(d.pegInProxy));
        address registry = pegIn.getPegInAddressRegistry();
        address configurations = pegIn.getFlyoverConfigurations();

        assertTrue(
            registry != address(0),
            "PegInAddressRegistry should be set"
        );
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

    function _expectRegtestSeedsForbidden(uint256 chainId) private {
        vm.expectRevert(
            abi.encodeWithSelector(
                HelperConfig
                    .FlyoverConfigurationsRegtestForbiddenOnLiveNetwork
                    .selector,
                chainId
            )
        );
    }

    function _runDeployFlyoverOnChain(
        uint256 chainId,
        string memory signerEnv
    ) private {
        vm.chainId(chainId);
        vm.setEnv(signerEnv, TEST_SIGNER_KEY);
        DeployFlyover deployer = new DeployFlyover();
        _expectRegtestSeedsForbidden(chainId);
        deployer.run();
    }

    function _runDeployFlyoverConfigurationsOnChain(
        uint256 chainId,
        string memory signerEnv
    ) private {
        vm.chainId(chainId);
        vm.setEnv(signerEnv, TEST_SIGNER_KEY);
        DeployFlyoverConfigurations deployer = new DeployFlyoverConfigurations();
        _expectRegtestSeedsForbidden(chainId);
        deployer.run();
    }
}
