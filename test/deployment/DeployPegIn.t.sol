// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {PegInContract} from "../../src/PegInContract.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {BridgeMock} from "../../src/test-contracts/BridgeMock.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/**
 * @title DeployPegInTest
 * @notice Test for PegInContract deployment
 */
contract DeployPegInTest is Test {
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
            (deployer, cfg.adminDelay, cfg.minimumCollateral, cfg.resignDelayBlocks, cfg.rewardPercentage)
        );
        collateralManagementProxy = address(new TransparentUpgradeableProxy(cmImpl, cmAdmin, cmInitData));
    }

    function _deployPegIn(address deployer, HelperConfig.FlyoverConfig memory cfg) internal returns (address) {
        address impl = address(new PegInContract());
        address admin = address(new ProxyAdmin(deployer));
        bytes memory initData = abi.encodeCall(
            PegInContract.initialize,
            (deployer, payable(address(bridgeMock)), cfg.dustThreshold, cfg.minimumPegIn,
             collateralManagementProxy, cfg.mainnet, cfg.daoFeePercentage, cfg.daoFeeCollector)
        );
        return address(new TransparentUpgradeableProxy(impl, admin, initData));
    }

    function test_DeploymentFlow() public {
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        address proxy = _deployPegIn(deployer, cfg);
        PegInContract pegIn = PegInContract(payable(proxy));

        assertEq(pegIn.getMinPegIn(), cfg.minimumPegIn, "Min PegIn mismatch");
        assertEq(pegIn.dustThreshold(), cfg.dustThreshold, "Dust threshold mismatch");
    }

    function test_DeployUsingInlineDeployment() public {
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        address proxy = _deployPegIn(deployer, cfg);

        assertTrue(proxy != address(0), "Proxy should not be zero");

        PegInContract pegIn = PegInContract(payable(proxy));
        assertEq(pegIn.getMinPegIn(), cfg.minimumPegIn, "Min PegIn mismatch");
    }

    function test_IntegrationWithCollateralManagement() public {
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        address piProxy = _deployPegIn(deployer, cfg);
        CollateralManagementContract cm = CollateralManagementContract(payable(collateralManagementProxy));

        bytes32 collateralSlasherRole = cm.COLLATERAL_SLASHER();
        cm.grantRole(collateralSlasherRole, piProxy);

        assertTrue(cm.hasRole(collateralSlasherRole, piProxy), "PegIn should have COLLATERAL_SLASHER");
    }

    function test_RolesAreSetCorrectly() public {
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        address proxy = _deployPegIn(deployer, cfg);
        PegInContract pegIn = PegInContract(payable(proxy));

        bytes32 defaultAdminRole = pegIn.DEFAULT_ADMIN_ROLE();
        assertTrue(pegIn.hasRole(defaultAdminRole, deployer), "Deployer should have DEFAULT_ADMIN_ROLE");
    }

    function test_DaoConfigurationSet() public {
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        address proxy = _deployPegIn(deployer, cfg);
        PegInContract pegIn = PegInContract(payable(proxy));

        assertEq(pegIn.getFeePercentage(), cfg.daoFeePercentage, "DAO fee percentage mismatch");
        assertEq(pegIn.getFeeCollector(), cfg.daoFeeCollector, "DAO fee collector mismatch");
    }
}
