// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ProxyReader} from "../../script/helpers/ProxyReader.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {FlyoverConfigurations} from "../../src/FlyoverConfigurations.sol";
import {PauseRegistry} from "../../src/PauseRegistry.sol";
import {PegOutContract} from "../../src/PegOutContract.sol";
import {PegOutEscrow} from "../../src/PegOutEscrow.sol";
import {IPauseRegistry} from "../../src/interfaces/IPauseRegistry.sol";
import {FlyoverConfigurationsRegtest} from "../../src/libraries/FlyoverConfigurationsRegtest.sol";
import {BridgeMock} from "../../src/test-contracts/BridgeMock.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/**
 * @title DeployPegOutEscrowTest
 * @notice Test for PegOutEscrow deployment and PegOut / slash-role wiring
 */
contract DeployPegOutEscrowTest is Test {
    HelperConfig public helperConfig;
    BridgeMock public bridgeMock;
    address public collateralManagementProxy;
    address public pauseRegistryProxy;
    address public pegOutProxy;
    address public configurationsProxy;

    function setUp() public {
        helperConfig = new HelperConfig();
        bridgeMock = new BridgeMock();

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        PauseRegistry prImpl = new PauseRegistry();
        pauseRegistryProxy = address(
            new TransparentUpgradeableProxy(
                address(prImpl),
                deployer,
                abi.encodeCall(prImpl.initialize, (0, deployer))
            )
        );

        address cmImpl = address(new CollateralManagementContract());
        collateralManagementProxy = address(
            new TransparentUpgradeableProxy(
                cmImpl,
                deployer,
                abi.encodeCall(
                    CollateralManagementContract.initialize,
                    (
                        deployer,
                        cfg.adminDelay,
                        cfg.minimumCollateral,
                        cfg.resignDelayBlocks,
                        cfg.rewardPercentage,
                        PauseRegistry(pauseRegistryProxy)
                    )
                )
            )
        );

        address pegOutImpl = address(new PegOutContract());
        pegOutProxy = address(
            new TransparentUpgradeableProxy(
                pegOutImpl,
                deployer,
                abi.encodeCall(
                    PegOutContract.initialize,
                    (
                        deployer,
                        payable(address(bridgeMock)),
                        cfg.dustThreshold,
                        collateralManagementProxy,
                        cfg.mainnet,
                        cfg.btcBlockTime,
                        PauseRegistry(pauseRegistryProxy)
                    )
                )
            )
        );

        address configsImpl = address(new FlyoverConfigurations());
        configurationsProxy = address(
            new TransparentUpgradeableProxy(
                configsImpl,
                deployer,
                abi.encodeCall(
                    FlyoverConfigurations.initialize,
                    (
                        deployer,
                        cfg.adminDelay,
                        FlyoverConfigurationsRegtest.TIMELOCK_DELAY,
                        FlyoverConfigurationsRegtest.pegInConfig(),
                        FlyoverConfigurationsRegtest.pegInMin(),
                        FlyoverConfigurationsRegtest.pegInMax()
                    )
                )
            )
        );
        FlyoverConfigurations(payable(configurationsProxy)).initializePegOut(
            FlyoverConfigurationsRegtest.pegOutConfig(),
            FlyoverConfigurationsRegtest.pegOutMin(),
            FlyoverConfigurationsRegtest.pegOutMax()
        );
    }

    function _deployEscrow(address deployer, uint48 adminDelay)
        internal
        returns (address proxy)
    {
        address impl = address(new PegOutEscrow());
        proxy = address(
            new TransparentUpgradeableProxy(
                impl,
                deployer,
                abi.encodeCall(
                    PegOutEscrow.initialize,
                    (
                        deployer,
                        adminDelay,
                        IPauseRegistry(pauseRegistryProxy),
                        pegOutProxy,
                        collateralManagementProxy,
                        configurationsProxy
                    )
                )
            )
        );

        PegOutContract(payable(pegOutProxy)).setPegOutEscrow(proxy);
        CollateralManagementContract cm = CollateralManagementContract(
            payable(collateralManagementProxy)
        );
        cm.grantRole(cm.COLLATERAL_SLASHER(), proxy);
    }

    function test_DeployPegOutEscrow_WiresPegOutAndSlasher() public {
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        address proxy = _deployEscrow(deployer, cfg.adminDelay);
        PegOutEscrow escrow = PegOutEscrow(payable(proxy));

        assertEq(escrow.getPegOutContract(), pegOutProxy);
        assertEq(escrow.getFlyoverConfigurations(), configurationsProxy);
        assertEq(
            Ownable(ProxyReader.readAdmin(vm, proxy)).owner(),
            deployer,
            "PegOutEscrow ProxyAdmin owner mismatch"
        );

        CollateralManagementContract cm = CollateralManagementContract(
            payable(collateralManagementProxy)
        );
        assertTrue(
            cm.hasRole(cm.COLLATERAL_SLASHER(), proxy),
            "Escrow should have COLLATERAL_SLASHER"
        );

        // Escrow is wired: non-escrow callers hit OnlyPegOutEscrow (not PegOutEscrowNotSet).
        PegOutContract pegOut = PegOutContract(payable(pegOutProxy));
        vm.expectRevert(
            abi.encodeWithSelector(
                PegOutContract.OnlyPegOutEscrow.selector,
                address(this)
            )
        );
        pegOut.registerClaimedPegOut(bytes32(uint256(1)), "");
    }

    function test_DeployPegOutEscrow_SeedsRegtestPegOutConfig() public {
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        _deployEscrow(address(this), cfg.adminDelay);

        FlyoverConfigurations configs = FlyoverConfigurations(
            payable(configurationsProxy)
        );
        assertEq(
            configs.getPegOutConfiguration().fixedFee,
            FlyoverConfigurationsRegtest.pegOutConfig().fixedFee
        );
        assertEq(
            configs.getPegOutConfiguration().claimWindow,
            FlyoverConfigurationsRegtest.pegOutConfig().claimWindow
        );
    }

    function test_DeployPegOutEscrow_IsUpgradeable() public {
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);
        address proxy = _deployEscrow(deployer, cfg.adminDelay);

        ProxyAdmin proxyAdmin = ProxyAdmin(ProxyReader.readAdmin(vm, proxy));
        address oldImpl = ProxyReader.readImplementation(vm, proxy);
        address newImpl = address(new PegOutEscrow());
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(proxy),
            newImpl,
            ""
        );
        assertEq(ProxyReader.readImplementation(vm, proxy), newImpl);
        assertTrue(oldImpl != newImpl);
    }
}
