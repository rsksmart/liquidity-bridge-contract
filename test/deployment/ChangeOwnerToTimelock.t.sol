// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

// Legacy imports
import {ChangeOwnerToTimelock as LegacyChangeOwnerToTimelock} from "../../script/legacy/deployment/ChangeOwnerToTimelock.s.sol";
import {LiquidityBridgeContract} from "../../src/legacy/LiquidityBridgeContract.sol";
import {LiquidityBridgeContractProxy} from "../../src/legacy/LiquidityBridgeContractProxy.sol";
import {LiquidityBridgeContractAdmin} from "../../src/legacy/LiquidityBridgeContractAdmin.sol";

// Split imports
import {ChangeOwnerToTimelock as SplitChangeOwnerToTimelock} from "../../script/deployment/ChangeOwnerToTimelock.s.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {FlyoverDiscovery} from "../../src/FlyoverDiscovery.sol";
import {PegInContract} from "../../src/PegInContract.sol";
import {PegOutContract} from "../../src/PegOutContract.sol";
import {BridgeMock} from "../../src/test-contracts/BridgeMock.sol";

// ============================================================
// Legacy Tests
// ============================================================

contract LegacyChangeOwnerToTimelockTest is Test {
    bytes32 internal constant ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    HelperConfig public helperConfig;
    LegacyChangeOwnerToTimelock public script;
    LiquidityBridgeContract public lbcImpl;
    LiquidityBridgeContractProxy public proxy;
    LiquidityBridgeContractAdmin public admin;

    address public proposer;
    address public executor;
    uint256 public minDelay;

    function setUp() public {
        helperConfig = new HelperConfig();
        script = new LegacyChangeOwnerToTimelock();

        proposer = makeAddr("proposer");
        executor = makeAddr("executor");
        minDelay = 7 days;

        HelperConfig.NetworkConfig memory cfg = helperConfig.getConfig();

        lbcImpl = new LiquidityBridgeContract();
        admin = new LiquidityBridgeContractAdmin();

        bytes memory initData = abi.encodeCall(
            LiquidityBridgeContract.initialize,
            (
                payable(cfg.bridge),
                cfg.minimumCollateral,
                cfg.minimumPegIn,
                cfg.rewardPercentage,
                cfg.resignDelayBlocks,
                cfg.dustThreshold,
                cfg.btcBlockTime,
                cfg.mainnet
            )
        );
        proxy = new LiquidityBridgeContractProxy(
            address(lbcImpl),
            address(admin),
            initData
        );
    }

    function test_ScriptTransfersProxyAdminToTimelock() public {
        HelperConfig.NetworkConfig memory cfg = helperConfig.getConfig();
        cfg.timelockProposer = proposer;
        cfg.timelockExecutor = executor;
        cfg.timelockMinDelay = minDelay;

        LiquidityBridgeContractAdmin slotAdmin = _getProxyAdmin();
        vm.prank(address(admin));
        slotAdmin.transferOwnership(address(script));

        TimelockController timelock = script.execute(address(proxy), cfg);

        assertEq(
            slotAdmin.owner(),
            address(timelock),
            "ProxyAdmin owner should be timelock"
        );
        assertEq(timelock.getMinDelay(), minDelay, "minDelay mismatch");
        assertTrue(
            timelock.hasRole(timelock.PROPOSER_ROLE(), proposer),
            "proposer role missing"
        );
        assertTrue(
            timelock.hasRole(timelock.EXECUTOR_ROLE(), executor),
            "executor role missing"
        );
    }

    function test_ProxyAdminStoredInExpectedSlot() public view {
        address proxyAdminAddress = address(
            uint160(uint256(vm.load(address(proxy), ADMIN_SLOT)))
        );
        assertTrue(proxyAdminAddress != address(0), "EIP-1967 admin missing");
    }

    function _getProxyAdmin()
        internal
        view
        returns (LiquidityBridgeContractAdmin)
    {
        address proxyAdminAddress = address(
            uint160(uint256(vm.load(address(proxy), ADMIN_SLOT)))
        );
        return LiquidityBridgeContractAdmin(proxyAdminAddress);
    }
}

// ============================================================
// Split Architecture Tests
// ============================================================

contract SplitChangeOwnerToTimelockTest is Test {
    HelperConfig public helperConfig;
    SplitChangeOwnerToTimelock public script;
    BridgeMock public bridgeMock;

    CollateralManagementContract public collateralManagement;
    FlyoverDiscovery public discovery;
    PegInContract public pegInContract;
    PegOutContract public pegOutContract;
    address public proxyAdmin;

    address public deployer;
    address public proposer;
    address public executor;
    uint256 public minDelay;

    function setUp() public {
        deployer = address(this);
        helperConfig = new HelperConfig();
        script = new SplitChangeOwnerToTimelock();
        bridgeMock = new BridgeMock();

        proposer = makeAddr("proposer");
        executor = makeAddr("executor");
        minDelay = 7 days;

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        _deployAll(deployer, cfg);
    }

    function test_ScriptTransfersProxyAdminToTimelock() public {
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        cfg.timelockProposer = proposer;
        cfg.timelockExecutor = executor;
        cfg.timelockMinDelay = minDelay;

        ProxyAdmin(proxyAdmin).transferOwnership(address(script));

        TimelockController timelock = script.execute(proxyAdmin, cfg);

        assertEq(
            ProxyAdmin(proxyAdmin).owner(),
            address(timelock),
            "ProxyAdmin owner should be timelock"
        );
        assertEq(timelock.getMinDelay(), minDelay, "minDelay mismatch");
        assertTrue(
            timelock.hasRole(timelock.PROPOSER_ROLE(), proposer),
            "proposer role missing"
        );
        assertTrue(
            timelock.hasRole(timelock.EXECUTOR_ROLE(), executor),
            "executor role missing"
        );
    }

    function test_ProxyAdminOwnedByTimelockBlocksDirectUpgrade() public {
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        cfg.timelockProposer = proposer;
        cfg.timelockExecutor = executor;
        cfg.timelockMinDelay = minDelay;

        ProxyAdmin(proxyAdmin).transferOwnership(address(script));

        TimelockController timelock = script.execute(proxyAdmin, cfg);

        assertEq(
            ProxyAdmin(proxyAdmin).owner(),
            address(timelock),
            "ProxyAdmin should be owned by timelock"
        );

        address newImpl = address(new CollateralManagementContract());
        vm.expectRevert();
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(collateralManagement)),
            newImpl,
            ""
        );
    }

    function test_RevertsIfNonOwnerCallsExecute() public {
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        cfg.timelockProposer = proposer;
        cfg.timelockExecutor = executor;
        cfg.timelockMinDelay = minDelay;

        vm.expectRevert();
        script.execute(proxyAdmin, cfg);
    }

    function test_RevertsIfTimelockProposerIsZero() public {
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        cfg.timelockProposer = address(0);
        cfg.timelockExecutor = executor;

        vm.expectRevert(
            SplitChangeOwnerToTimelock.TimelockProposerIsZero.selector
        );
        script.execute(proxyAdmin, cfg);
    }

    function test_RevertsIfTimelockExecutorIsZero() public {
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        cfg.timelockProposer = proposer;
        cfg.timelockExecutor = address(0);

        vm.expectRevert(
            SplitChangeOwnerToTimelock.TimelockExecutorIsZero.selector
        );
        script.execute(proxyAdmin, cfg);
    }

    // ============================================================
    // Helpers
    // ============================================================

    function _deployAll(
        address admin_,
        HelperConfig.FlyoverConfig memory cfg
    ) internal {
        proxyAdmin = address(new ProxyAdmin(admin_));
        _deployCollateralManagement(admin_, cfg);
        _deployFlyoverDiscovery(admin_, cfg);
        _deployPegIn(admin_, cfg);
        _deployPegOut(admin_, cfg);
    }

    function _deployCollateralManagement(
        address admin_,
        HelperConfig.FlyoverConfig memory cfg
    ) private {
        address impl = address(new CollateralManagementContract());
        address proxy = address(
            new TransparentUpgradeableProxy(
                impl,
                proxyAdmin,
                abi.encodeCall(
                    CollateralManagementContract.initialize,
                    (
                        admin_,
                        cfg.adminDelay,
                        cfg.minimumCollateral,
                        cfg.resignDelayBlocks,
                        cfg.rewardPercentage
                    )
                )
            )
        );
        collateralManagement = CollateralManagementContract(payable(proxy));
    }

    function _deployFlyoverDiscovery(
        address admin_,
        HelperConfig.FlyoverConfig memory cfg
    ) private {
        address impl = address(new FlyoverDiscovery());
        address proxy = address(
            new TransparentUpgradeableProxy(
                impl,
                proxyAdmin,
                abi.encodeCall(
                    FlyoverDiscovery.initialize,
                    (admin_, cfg.adminDelay, address(collateralManagement))
                )
            )
        );
        discovery = FlyoverDiscovery(proxy);
    }

    function _deployPegIn(
        address admin_,
        HelperConfig.FlyoverConfig memory cfg
    ) private {
        address impl = address(new PegInContract());
        address proxy = address(
            new TransparentUpgradeableProxy(
                impl,
                proxyAdmin,
                abi.encodeCall(
                    PegInContract.initialize,
                    (
                        admin_,
                        payable(address(bridgeMock)),
                        cfg.dustThreshold,
                        cfg.minimumPegIn,
                        address(collateralManagement),
                        cfg.mainnet,
                        cfg.daoFeePercentage,
                        cfg.daoFeeCollector
                    )
                )
            )
        );
        pegInContract = PegInContract(payable(proxy));
    }

    function _deployPegOut(
        address admin_,
        HelperConfig.FlyoverConfig memory cfg
    ) private {
        address impl = address(new PegOutContract());
        address proxy = address(
            new TransparentUpgradeableProxy(
                impl,
                proxyAdmin,
                abi.encodeCall(
                    PegOutContract.initialize,
                    (
                        admin_,
                        payable(address(bridgeMock)),
                        cfg.dustThreshold,
                        address(collateralManagement),
                        cfg.mainnet,
                        cfg.btcBlockTime,
                        cfg.daoFeePercentage,
                        cfg.daoFeeCollector
                    )
                )
            )
        );
        pegOutContract = PegOutContract(payable(proxy));
    }
}
