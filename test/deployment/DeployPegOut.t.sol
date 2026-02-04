// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {PegOutContract} from "../../src/PegOutContract.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {BridgeMock} from "../../src/test-contracts/BridgeMock.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/**
 * @title DeployPegOutTest
 * @notice Test for PegOutContract deployment
 */
contract DeployPegOutTest is Test {
    HelperConfig public helperConfig;
    BridgeMock public bridgeMock;
    address public collateralManagementProxy;

    function setUp() public {
        helperConfig = new HelperConfig();
        bridgeMock = new BridgeMock();

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        address cmImpl = address(new CollateralManagementContract());
        address cmAdmin = address(new ProxyAdmin(deployer));
        bytes memory cmInitData = abi.encodeCall(
            CollateralManagementContract.initialize,
            (
                deployer,
                cfg.adminDelay,
                cfg.minimumCollateral,
                cfg.resignDelayBlocks,
                cfg.rewardPercentage
            )
        );
        collateralManagementProxy = address(
            new TransparentUpgradeableProxy(cmImpl, cmAdmin, cmInitData)
        );
    }

    function _deployPegOut(
        address deployer,
        HelperConfig.FlyoverConfig memory cfg
    ) internal returns (address) {
        address impl = address(new PegOutContract());
        address admin = address(new ProxyAdmin(deployer));
        bytes memory initData = abi.encodeCall(
            PegOutContract.initialize,
            (
                deployer,
                payable(address(bridgeMock)),
                cfg.dustThreshold,
                collateralManagementProxy,
                cfg.mainnet,
                cfg.btcBlockTime
            )
        );
        return address(new TransparentUpgradeableProxy(impl, admin, initData));
    }

    function test_DeploymentFlow() public {
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        address proxy = _deployPegOut(deployer, cfg);
        PegOutContract pegOut = PegOutContract(payable(proxy));

        assertEq(
            pegOut.dustThreshold(),
            cfg.dustThreshold,
            "Dust threshold mismatch"
        );
        assertEq(
            pegOut.btcBlockTime(),
            cfg.btcBlockTime,
            "BTC block time mismatch"
        );
    }

    function test_DeployUsingInlineDeployment() public {
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        address proxy = _deployPegOut(deployer, cfg);

        assertTrue(proxy != address(0), "Proxy should not be zero");

        PegOutContract pegOut = PegOutContract(payable(proxy));
        assertEq(
            pegOut.btcBlockTime(),
            cfg.btcBlockTime,
            "BTC block time mismatch"
        );
    }

    function test_IntegrationWithCollateralManagement() public {
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        address poProxy = _deployPegOut(deployer, cfg);
        CollateralManagementContract cm = CollateralManagementContract(
            payable(collateralManagementProxy)
        );

        bytes32 collateralSlasherRole = cm.COLLATERAL_SLASHER();
        cm.grantRole(collateralSlasherRole, poProxy);

        assertTrue(
            cm.hasRole(collateralSlasherRole, poProxy),
            "PegOut should have COLLATERAL_SLASHER"
        );
    }

    function test_RolesAreSetCorrectly() public {
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        address proxy = _deployPegOut(deployer, cfg);
        PegOutContract pegOut = PegOutContract(payable(proxy));

        bytes32 defaultAdminRole = pegOut.DEFAULT_ADMIN_ROLE();
        assertTrue(
            pegOut.hasRole(defaultAdminRole, deployer),
            "Deployer should have DEFAULT_ADMIN_ROLE"
        );
    }

}
