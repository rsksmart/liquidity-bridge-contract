// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
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
import {AccessControlDefaultAdminRulesUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";

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

    address public deployer;
    address public proposer;
    address public executor;
    uint256 public minDelay;

    function setUp() public {
        deployer = address(this);
        helperConfig = new HelperConfig();
        script = new LegacyChangeOwnerToTimelock();

        proposer = makeAddr("proposer");
        executor = makeAddr("executor");
        minDelay = 7 days;

        HelperConfig.NetworkConfig memory cfg = helperConfig.getConfig();
        cfg.timelockProposer = proposer;
        cfg.timelockExecutor = executor;
        cfg.timelockMinDelay = minDelay;

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

    function _grantScriptOwnership() internal {
        LiquidityBridgeContract lbcProxy = LiquidityBridgeContract(
            payable(address(proxy))
        );
        lbcProxy.transferOwnership(address(script));

        // The TransparentUpgradeableProxy creates an internal ProxyAdmin whose owner
        // is the `admin` contract (LiquidityBridgeContractAdmin). Transfer the
        // slot-level ProxyAdmin ownership from `admin` to the script.
        LiquidityBridgeContractAdmin slotAdmin = _getProxyAdmin();
        vm.prank(address(admin));
        slotAdmin.transferOwnership(address(script));
    }

    function test_ScriptTransfersLegacyOwnershipsToTimelock() public {
        HelperConfig.NetworkConfig memory cfg = helperConfig.getConfig();
        cfg.timelockProposer = proposer;
        cfg.timelockExecutor = executor;
        cfg.timelockMinDelay = minDelay;

        _grantScriptOwnership();

        TimelockController timelock = script.execute(address(proxy), cfg);

        LiquidityBridgeContract lbcProxy = LiquidityBridgeContract(
            payable(address(proxy))
        );
        assertEq(
            lbcProxy.owner(),
            address(timelock),
            "LBC owner should be timelock"
        );

        LiquidityBridgeContractAdmin actualAdmin = _getProxyAdmin();
        assertEq(
            actualAdmin.owner(),
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

    function test_OwnerOnlyOperationIsDelayedByTimelock() public {
        HelperConfig.NetworkConfig memory cfg = helperConfig.getConfig();
        cfg.timelockProposer = proposer;
        cfg.timelockExecutor = executor;
        cfg.timelockMinDelay = minDelay;

        _grantScriptOwnership();

        TimelockController timelock = script.execute(address(proxy), cfg);
        LiquidityBridgeContract lbcProxy = LiquidityBridgeContract(
            payable(address(proxy))
        );

        address newOwner = makeAddr("newOwner");
        bytes memory payload = abi.encodeWithSignature(
            "transferOwnership(address)",
            newOwner
        );
        bytes32 predecessor = bytes32(0);
        bytes32 salt = keccak256("owner-op");

        vm.expectRevert();
        lbcProxy.transferOwnership(newOwner);

        vm.prank(proposer);
        timelock.schedule(
            address(lbcProxy),
            0,
            payload,
            predecessor,
            salt,
            minDelay
        );

        vm.prank(executor);
        vm.expectRevert();
        timelock.execute(address(lbcProxy), 0, payload, predecessor, salt);

        vm.warp(block.timestamp + minDelay);
        vm.prank(executor);
        timelock.execute(address(lbcProxy), 0, payload, predecessor, salt);

        assertEq(lbcProxy.owner(), newOwner, "timelocked owner-op failed");
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

    function test_ScriptInitiatesAdminTransfersAndTransfersProxyAdmin() public {
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        cfg.timelockProposer = proposer;
        cfg.timelockExecutor = executor;
        cfg.timelockMinDelay = minDelay;

        SplitChangeOwnerToTimelock.ProxyAddresses
            memory proxies = _buildProxyAddresses();
        _grantScriptAdminRights();

        TimelockController timelock = script.execute(proxies, cfg);

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

        _assertPendingAdmin(address(collateralManagement), address(timelock));
        _assertPendingAdmin(address(discovery), address(timelock));
        _assertPendingAdmin(address(pegInContract), address(timelock));
        _assertPendingAdmin(address(pegOutContract), address(timelock));

        assertEq(
            collateralManagement.defaultAdmin(),
            address(script),
            "CM: admin should still be script before accept"
        );
    }

    function test_TimelockCanAcceptAdminAfterDelay() public {
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        cfg.timelockProposer = proposer;
        cfg.timelockExecutor = executor;
        cfg.timelockMinDelay = minDelay;

        SplitChangeOwnerToTimelock.ProxyAddresses
            memory proxies = _buildProxyAddresses();
        _grantScriptAdminRights();

        TimelockController timelock = script.execute(proxies, cfg);

        (, uint48 schedule) = collateralManagement.pendingDefaultAdmin();
        vm.warp(schedule);

        address[] memory targets = new address[](4);
        targets[0] = address(collateralManagement);
        targets[1] = address(discovery);
        targets[2] = address(pegInContract);
        targets[3] = address(pegOutContract);

        bytes memory acceptPayload = abi.encodeWithSignature(
            "acceptDefaultAdminTransfer()"
        );

        for (uint256 i = 0; i < targets.length; i++) {
            bytes32 salt = keccak256(abi.encodePacked("accept-admin-", i));

            vm.prank(proposer);
            timelock.schedule(
                targets[i],
                0,
                acceptPayload,
                bytes32(0),
                salt,
                minDelay
            );

            vm.warp(block.timestamp + minDelay);

            vm.prank(executor);
            timelock.execute(targets[i], 0, acceptPayload, bytes32(0), salt);
        }

        assertEq(
            collateralManagement.defaultAdmin(),
            address(timelock),
            "CM admin mismatch"
        );
        assertEq(
            discovery.defaultAdmin(),
            address(timelock),
            "Discovery admin mismatch"
        );
        assertEq(
            pegInContract.defaultAdmin(),
            address(timelock),
            "PegIn admin mismatch"
        );
        assertEq(
            pegOutContract.defaultAdmin(),
            address(timelock),
            "PegOut admin mismatch"
        );
    }

    function test_AdminOperationIsDelayedByTimelock() public {
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        cfg.timelockProposer = proposer;
        cfg.timelockExecutor = executor;
        cfg.timelockMinDelay = minDelay;

        SplitChangeOwnerToTimelock.ProxyAddresses
            memory proxies = _buildProxyAddresses();
        _grantScriptAdminRights();

        TimelockController timelock = script.execute(proxies, cfg);
        _acceptAllAdminTransfers(timelock);

        uint256 newMinCollateral = 999 ether;
        bytes memory payload = abi.encodeWithSignature(
            "setMinCollateral(uint256)",
            newMinCollateral
        );
        bytes32 salt = keccak256("set-min-collateral");

        vm.prank(proposer);
        timelock.schedule(
            address(collateralManagement),
            0,
            payload,
            bytes32(0),
            salt,
            minDelay
        );

        vm.prank(executor);
        vm.expectRevert();
        timelock.execute(
            address(collateralManagement),
            0,
            payload,
            bytes32(0),
            salt
        );

        vm.warp(block.timestamp + minDelay);
        vm.prank(executor);
        timelock.execute(
            address(collateralManagement),
            0,
            payload,
            bytes32(0),
            salt
        );

        assertEq(
            collateralManagement.getMinCollateral(),
            newMinCollateral,
            "setMinCollateral via timelock failed"
        );
    }

    function test_RevertsIfNonAdminCallsExecute() public {
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        cfg.timelockProposer = proposer;
        cfg.timelockExecutor = executor;
        cfg.timelockMinDelay = minDelay;

        SplitChangeOwnerToTimelock.ProxyAddresses
            memory proxies = _buildProxyAddresses();

        vm.expectRevert();
        script.execute(proxies, cfg);
    }

    function test_RevertsIfTimelockProposerIsZero() public {
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        cfg.timelockProposer = address(0);
        cfg.timelockExecutor = executor;

        SplitChangeOwnerToTimelock.ProxyAddresses
            memory proxies = _buildProxyAddresses();

        vm.expectRevert(
            SplitChangeOwnerToTimelock.TimelockProposerIsZero.selector
        );
        script.execute(proxies, cfg);
    }

    function test_RevertsIfTimelockExecutorIsZero() public {
        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        cfg.timelockProposer = proposer;
        cfg.timelockExecutor = address(0);

        SplitChangeOwnerToTimelock.ProxyAddresses
            memory proxies = _buildProxyAddresses();

        vm.expectRevert(
            SplitChangeOwnerToTimelock.TimelockExecutorIsZero.selector
        );
        script.execute(proxies, cfg);
    }

    // ============================================================
    // Helpers
    // ============================================================

    function _buildProxyAddresses()
        internal
        view
        returns (SplitChangeOwnerToTimelock.ProxyAddresses memory)
    {
        return
            SplitChangeOwnerToTimelock.ProxyAddresses({
                collateralManagement: address(collateralManagement),
                flyoverDiscovery: address(discovery),
                pegIn: address(pegInContract),
                pegOut: address(pegOutContract),
                proxyAdmin: proxyAdmin
            });
    }

    /// @dev Transfers DEFAULT_ADMIN_ROLE on all 4 contracts and ProxyAdmin
    ///      ownership to the script contract, simulating a deployer handing off
    ///      control before the script runs.
    function _grantScriptAdminRights() internal {
        collateralManagement.beginDefaultAdminTransfer(address(script));
        discovery.beginDefaultAdminTransfer(address(script));
        pegInContract.beginDefaultAdminTransfer(address(script));
        pegOutContract.beginDefaultAdminTransfer(address(script));

        vm.warp(block.timestamp + 1);

        vm.startPrank(address(script));
        collateralManagement.acceptDefaultAdminTransfer();
        discovery.acceptDefaultAdminTransfer();
        pegInContract.acceptDefaultAdminTransfer();
        pegOutContract.acceptDefaultAdminTransfer();
        vm.stopPrank();

        ProxyAdmin(proxyAdmin).transferOwnership(address(script));
    }

    function _assertPendingAdmin(
        address proxy,
        address expectedPending
    ) internal view {
        (address pendingAdmin, ) = AccessControlDefaultAdminRulesUpgradeable(
            proxy
        ).pendingDefaultAdmin();
        assertEq(pendingAdmin, expectedPending, "pending admin mismatch");
    }

    function _acceptAllAdminTransfers(TimelockController timelock) internal {
        (, uint48 schedule) = collateralManagement.pendingDefaultAdmin();
        vm.warp(schedule);

        address[] memory targets = new address[](4);
        targets[0] = address(collateralManagement);
        targets[1] = address(discovery);
        targets[2] = address(pegInContract);
        targets[3] = address(pegOutContract);

        bytes memory acceptPayload = abi.encodeWithSignature(
            "acceptDefaultAdminTransfer()"
        );

        for (uint256 i = 0; i < targets.length; i++) {
            bytes32 salt = keccak256(abi.encodePacked("accept-admin-", i));

            vm.prank(proposer);
            timelock.schedule(
                targets[i],
                0,
                acceptPayload,
                bytes32(0),
                salt,
                minDelay
            );

            vm.warp(block.timestamp + minDelay);

            vm.prank(executor);
            timelock.execute(targets[i], 0, acceptPayload, bytes32(0), salt);
        }
    }

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
