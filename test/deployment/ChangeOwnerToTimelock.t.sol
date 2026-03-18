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
import {PauseRegistry} from "../../src/PauseRegistry.sol";
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
        LiquidityBridgeContractAdmin slotAdmin = _getProxyAdmin();
        slotAdmin.transferOwnership(address(script));

        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        address[] memory executors = new address[](1);
        executors[0] = executor;

        TimelockController timelock = script.execute(
            address(proxy),
            minDelay,
            proposers,
            executors,
            address(0)
        );

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

    address public pauseRegistryProxy;
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

    function _buildRoles()
        internal
        view
        returns (address[] memory proposers, address[] memory executors)
    {
        proposers = new address[](1);
        proposers[0] = proposer;
        executors = new address[](1);
        executors[0] = executor;
    }

    function test_ScriptTransfersProxyAdminToTimelock() public {
        (
            address[] memory proposers,
            address[] memory executors
        ) = _buildRoles();

        ProxyAdmin(proxyAdmin).transferOwnership(address(script));

        TimelockController timelock = script.execute(
            proxyAdmin,
            minDelay,
            proposers,
            executors,
            address(0)
        );

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

    function test_MultipleProposersAndExecutors() public {
        address proposer2 = makeAddr("proposer2");
        address executor2 = makeAddr("executor2");

        address[] memory proposers = new address[](2);
        proposers[0] = proposer;
        proposers[1] = proposer2;
        address[] memory executors = new address[](2);
        executors[0] = executor;
        executors[1] = executor2;

        ProxyAdmin(proxyAdmin).transferOwnership(address(script));

        TimelockController timelock = script.execute(
            proxyAdmin,
            minDelay,
            proposers,
            executors,
            address(0)
        );

        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        assertTrue(
            timelock.hasRole(proposerRole, proposer),
            "proposer1 missing"
        );
        assertTrue(
            timelock.hasRole(proposerRole, proposer2),
            "proposer2 missing"
        );
        assertTrue(
            timelock.hasRole(executorRole, executor),
            "executor1 missing"
        );
        assertTrue(
            timelock.hasRole(executorRole, executor2),
            "executor2 missing"
        );
    }

    function test_AdminCanGrantRolesImmediately() public {
        (
            address[] memory proposers,
            address[] memory executors
        ) = _buildRoles();
        address timelockAdmin = makeAddr("timelockAdmin");

        ProxyAdmin(proxyAdmin).transferOwnership(address(script));

        TimelockController timelock = script.execute(
            proxyAdmin,
            minDelay,
            proposers,
            executors,
            timelockAdmin
        );

        assertTrue(
            timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), timelockAdmin),
            "admin should have DEFAULT_ADMIN_ROLE"
        );

        address newProposer = makeAddr("newProposer");
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        vm.prank(timelockAdmin);
        timelock.grantRole(proposerRole, newProposer);

        assertTrue(
            timelock.hasRole(proposerRole, newProposer),
            "new proposer should have role"
        );
    }

    function test_ProxyAdminOwnedByTimelockBlocksDirectUpgrade() public {
        (
            address[] memory proposers,
            address[] memory executors
        ) = _buildRoles();

        ProxyAdmin(proxyAdmin).transferOwnership(address(script));

        TimelockController timelock = script.execute(
            proxyAdmin,
            minDelay,
            proposers,
            executors,
            address(0)
        );

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
        (
            address[] memory proposers,
            address[] memory executors
        ) = _buildRoles();

        vm.expectRevert();
        script.execute(proxyAdmin, minDelay, proposers, executors, address(0));
    }

    function test_RevertsIfNoProposers() public {
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = executor;

        ProxyAdmin(proxyAdmin).transferOwnership(address(script));

        vm.expectRevert(
            SplitChangeOwnerToTimelock.NoProposersConfigured.selector
        );
        script.execute(proxyAdmin, minDelay, proposers, executors, address(0));
    }

    function test_RevertsIfNoExecutors() public {
        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        address[] memory executors = new address[](0);

        ProxyAdmin(proxyAdmin).transferOwnership(address(script));

        vm.expectRevert(
            SplitChangeOwnerToTimelock.NoExecutorsConfigured.selector
        );
        script.execute(proxyAdmin, minDelay, proposers, executors, address(0));
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
        PauseRegistry prImpl = new PauseRegistry();
        pauseRegistryProxy = address(
            new TransparentUpgradeableProxy(
                address(prImpl),
                proxyAdmin,
                abi.encodeCall(prImpl.initialize, (0, admin_))
            )
        );

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
                        cfg.rewardPercentage,
                        PauseRegistry(pauseRegistryProxy)
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
                    (
                        admin_,
                        cfg.adminDelay,
                        address(collateralManagement),
                        PauseRegistry(pauseRegistryProxy)
                    )
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
                        PauseRegistry(pauseRegistryProxy)
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
                        PauseRegistry(pauseRegistryProxy)
                    )
                )
            )
        );
        pegOutContract = PegOutContract(payable(proxy));
    }
}
