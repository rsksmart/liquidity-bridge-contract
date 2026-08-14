// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "lib/forge-std/src/Test.sol";
import "lib/forge-std/src/console.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ProxyReader} from "../../script/helpers/ProxyReader.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {FlyoverConfigurations} from "../../src/FlyoverConfigurations.sol";
import {FlyoverDiscovery} from "../../src/FlyoverDiscovery.sol";
import {PauseRegistry} from "../../src/PauseRegistry.sol";
import {PegInContract} from "../../src/PegInContract.sol";
import {PegOutContract} from "../../src/PegOutContract.sol";
import {PegOutEscrow} from "../../src/PegOutEscrow.sol";
import {IPauseRegistry} from "../../src/interfaces/IPauseRegistry.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {FlyoverConfigurationsRegtest} from "../../src/libraries/FlyoverConfigurationsRegtest.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {BridgeMock} from "../../src/test-contracts/BridgeMock.sol";

/**
 * @title DeployFlyoverTest
 * @notice Test for the DeployFlyover deployment pattern
 * @dev Tests full deployment of all Flyover contracts and role setup
 */
contract DeployFlyoverTest is Test {
    HelperConfig public helperConfig;
    BridgeMock public bridgeMock;

    // Deployed contracts
    address public pauseRegistryProxy;
    address public collateralManagementImplementation;
    address public flyoverDiscoveryImplementation;
    address public pegInImplementation;
    address public pegOutImplementation;
    address public pauseRegistryImplementation;
    CollateralManagementContract public collateralManagement;
    FlyoverDiscovery public discovery;
    PegInContract public pegInContract;
    PegOutContract public pegOutContract;
    FlyoverConfigurations public flyoverConfigurations;
    PegOutEscrow public pegOutEscrow;

    function setUp() public {
        helperConfig = new HelperConfig();
        bridgeMock = new BridgeMock();
    }

    function _assertTransparentProxyAdmin(
        address proxy,
        address deployer_
    ) internal view {
        address admin = ProxyReader.readAdmin(vm, proxy);
        assertTrue(admin != address(0), "ProxyAdmin should not be zero");
        assertEq(
            Ownable(admin).owner(),
            deployer_,
            "ProxyAdmin owner mismatch"
        );
    }

    function _assertAllProxyAdminsOwnedBy(address deployer_) internal view {
        _assertTransparentProxyAdmin(pauseRegistryProxy, deployer_);
        _assertTransparentProxyAdmin(address(collateralManagement), deployer_);
        _assertTransparentProxyAdmin(address(discovery), deployer_);
        _assertTransparentProxyAdmin(address(pegInContract), deployer_);
        _assertTransparentProxyAdmin(address(pegOutContract), deployer_);
        _assertTransparentProxyAdmin(address(flyoverConfigurations), deployer_);
        _assertTransparentProxyAdmin(address(pegOutEscrow), deployer_);
    }

    /// @notice Deploy all contracts inline (mirrors DeployFlyover script)
    function _deployAll(
        address deployer,
        HelperConfig.FlyoverConfig memory cfg
    ) internal {
        // 1) CollateralManagement
        _deployCollateralManagement(deployer, cfg);

        // 2) FlyoverDiscovery
        _deployFlyoverDiscovery(deployer, cfg);

        // 3) PegInContract
        _deployPegIn(deployer, cfg);

        // 4) PegOutContract
        _deployPegOut(deployer, cfg);

        // 5) FlyoverConfigurations
        _deployFlyoverConfigurations(deployer, cfg);

        // 6) PegOutEscrow (+ wire + slash role)
        _deployPegOutEscrow(deployer, cfg);
    }

    function _deployCollateralManagement(
        address deployer,
        HelperConfig.FlyoverConfig memory cfg
    ) private {
        PauseRegistry prImpl = new PauseRegistry();
        pauseRegistryImplementation = address(prImpl);
        pauseRegistryProxy = address(
            new TransparentUpgradeableProxy(
                address(prImpl),
                deployer,
                abi.encodeCall(prImpl.initialize, (0, deployer))
            )
        );
        address impl = address(new CollateralManagementContract());
        collateralManagementImplementation = impl;
        bytes memory initData = abi.encodeCall(
            CollateralManagementContract.initialize,
            (
                deployer,
                cfg.adminDelay,
                cfg.minimumCollateral,
                cfg.resignDelayBlocks,
                cfg.rewardPercentage,
                PauseRegistry(pauseRegistryProxy)
            )
        );
        address proxy = address(
            new TransparentUpgradeableProxy(impl, deployer, initData)
        );
        collateralManagement = CollateralManagementContract(payable(proxy));
    }

    function _deployFlyoverDiscovery(
        address deployer,
        HelperConfig.FlyoverConfig memory cfg
    ) private {
        address impl = address(new FlyoverDiscovery());
        flyoverDiscoveryImplementation = impl;
        bytes memory initData = abi.encodeCall(
            FlyoverDiscovery.initialize,
            (
                deployer,
                cfg.adminDelay,
                address(collateralManagement),
                PauseRegistry(pauseRegistryProxy)
            )
        );
        address proxy = address(
            new TransparentUpgradeableProxy(impl, deployer, initData)
        );
        discovery = FlyoverDiscovery(proxy);
    }

    function _deployPegIn(
        address deployer,
        HelperConfig.FlyoverConfig memory cfg
    ) private {
        address impl = address(new PegInContract());
        pegInImplementation = impl;
        bytes memory initData = abi.encodeCall(
            PegInContract.initialize,
            (
                deployer,
                payable(address(bridgeMock)),
                cfg.dustThreshold,
                cfg.minimumPegIn,
                address(collateralManagement),
                cfg.mainnet,
                PauseRegistry(pauseRegistryProxy)
            )
        );
        address proxy = address(
            new TransparentUpgradeableProxy(impl, deployer, initData)
        );
        pegInContract = PegInContract(payable(proxy));
    }

    function _deployPegOut(
        address deployer,
        HelperConfig.FlyoverConfig memory cfg
    ) private {
        address impl = address(new PegOutContract());
        pegOutImplementation = impl;
        bytes memory initData = abi.encodeCall(
            PegOutContract.initialize,
            (
                deployer,
                payable(address(bridgeMock)),
                cfg.dustThreshold,
                address(collateralManagement),
                cfg.mainnet,
                cfg.btcBlockTime,
                PauseRegistry(pauseRegistryProxy)
            )
        );
        address proxy = address(
            new TransparentUpgradeableProxy(impl, deployer, initData)
        );
        pegOutContract = PegOutContract(payable(proxy));
    }

    function _deployFlyoverConfigurations(
        address deployer,
        HelperConfig.FlyoverConfig memory cfg
    ) private {
        address impl = address(new FlyoverConfigurations());
        address proxy = address(
            new TransparentUpgradeableProxy(
                impl,
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
        flyoverConfigurations = FlyoverConfigurations(payable(proxy));
        flyoverConfigurations.initializePegOut(
            FlyoverConfigurationsRegtest.pegOutConfig(),
            FlyoverConfigurationsRegtest.pegOutMin(),
            FlyoverConfigurationsRegtest.pegOutMax()
        );
    }

    function _deployPegOutEscrow(
        address deployer,
        HelperConfig.FlyoverConfig memory cfg
    ) private {
        address impl = address(new PegOutEscrow());
        address proxy = address(
            new TransparentUpgradeableProxy(
                impl,
                deployer,
                abi.encodeCall(
                    PegOutEscrow.initialize,
                    (
                        deployer,
                        cfg.adminDelay,
                        IPauseRegistry(pauseRegistryProxy),
                        address(pegOutContract),
                        address(collateralManagement),
                        address(flyoverConfigurations)
                    )
                )
            )
        );
        pegOutEscrow = PegOutEscrow(payable(proxy));
        pegOutContract.setPegOutEscrow(proxy);
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_SLASHER(),
            proxy
        );
    }

    function test_FullDeploymentFlow() public {
        console.log("\n=== TEST FULL FLYOVER DEPLOYMENT ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        console.log("Deploying all Flyover contracts...");
        _deployAll(deployer, cfg);
        _assertAllProxyAdminsOwnedBy(deployer);

        // Verify all contracts deployed
        console.log("\n1. Verifying CollateralManagement...");
        assertTrue(
            address(collateralManagement) != address(0),
            "CM should not be zero"
        );
        console.log("   Proxy:", address(collateralManagement));

        console.log("\n2. Verifying FlyoverDiscovery...");
        assertTrue(address(discovery) != address(0), "FD should not be zero");
        console.log("   Proxy:", address(discovery));

        console.log("\n3. Verifying PegInContract...");
        assertTrue(
            address(pegInContract) != address(0),
            "PI should not be zero"
        );
        console.log("   Proxy:", address(pegInContract));

        console.log("\n4. Verifying PegOutContract...");
        assertTrue(
            address(pegOutContract) != address(0),
            "PO should not be zero"
        );
        console.log("   Proxy:", address(pegOutContract));

        console.log("\n5. Verifying FlyoverConfigurations...");
        assertTrue(
            address(flyoverConfigurations) != address(0),
            "Configs should not be zero"
        );
        console.log("   Proxy:", address(flyoverConfigurations));

        console.log("\n6. Verifying PegOutEscrow...");
        assertTrue(
            address(pegOutEscrow) != address(0),
            "Escrow should not be zero"
        );
        assertEq(pegOutEscrow.getPegOutContract(), address(pegOutContract));
        console.log("   Proxy:", address(pegOutEscrow));

        console.log("\n[PASS] All contracts deployed successfully!");
    }

    function test_RoleSetup() public {
        console.log("\n=== TEST ROLE SETUP ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        _deployAll(deployer, cfg);
        _assertAllProxyAdminsOwnedBy(deployer);

        bytes32 collateralAdderRole = collateralManagement.COLLATERAL_ADDER();
        bytes32 collateralSlasherRole = collateralManagement
            .COLLATERAL_SLASHER();

        // Setup roles
        console.log("Setting up roles...");
        collateralManagement.grantRole(collateralAdderRole, address(discovery));
        collateralManagement.grantRole(
            collateralSlasherRole,
            address(pegInContract)
        );
        collateralManagement.grantRole(
            collateralSlasherRole,
            address(pegOutContract)
        );
        collateralManagement.setFlyoverDiscovery(address(discovery));
        // Escrow slash role is granted inside _deployPegOutEscrow.

        // Verify FlyoverDiscovery has COLLATERAL_ADDER
        console.log("1. Checking FlyoverDiscovery has COLLATERAL_ADDER...");
        assertTrue(
            collateralManagement.hasRole(
                collateralAdderRole,
                address(discovery)
            ),
            "FlyoverDiscovery should have COLLATERAL_ADDER"
        );
        console.log("   FlyoverDiscovery has COLLATERAL_ADDER: true");

        // Verify PegInContract has COLLATERAL_SLASHER
        console.log("\n2. Checking PegInContract has COLLATERAL_SLASHER...");
        assertTrue(
            collateralManagement.hasRole(
                collateralSlasherRole,
                address(pegInContract)
            ),
            "PegInContract should have COLLATERAL_SLASHER"
        );
        console.log("   PegInContract has COLLATERAL_SLASHER: true");

        // Verify PegOutContract has COLLATERAL_SLASHER
        console.log("\n3. Checking PegOutContract has COLLATERAL_SLASHER...");
        assertTrue(
            collateralManagement.hasRole(
                collateralSlasherRole,
                address(pegOutContract)
            ),
            "PegOutContract should have COLLATERAL_SLASHER"
        );
        console.log("   PegOutContract has COLLATERAL_SLASHER: true");

        console.log("\n4. Checking PegOutEscrow has COLLATERAL_SLASHER...");
        assertTrue(
            collateralManagement.hasRole(
                collateralSlasherRole,
                address(pegOutEscrow)
            ),
            "PegOutEscrow should have COLLATERAL_SLASHER"
        );
        console.log("   PegOutEscrow has COLLATERAL_SLASHER: true");

        console.log("\n[PASS] All roles set up correctly!");
    }

    function test_ContractsAreInitializedCorrectly() public {
        console.log("\n=== TEST CONTRACTS INITIALIZED CORRECTLY ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        _deployAll(deployer, cfg);
        _assertAllProxyAdminsOwnedBy(deployer);

        // Check CollateralManagement
        console.log("1. CollateralManagement:");
        assertEq(
            collateralManagement.getMinCollateral(),
            cfg.minimumCollateral,
            "Min collateral mismatch"
        );
        assertEq(
            collateralManagement.getResignDelayInBlocks(),
            cfg.resignDelayBlocks,
            "Resign delay mismatch"
        );
        console.log(
            "   Min Collateral:",
            collateralManagement.getMinCollateral()
        );
        console.log(
            "   Resign Delay:",
            collateralManagement.getResignDelayInBlocks()
        );
        console.log("   Version:", collateralManagement.VERSION());

        // Check FlyoverDiscovery
        console.log("\n2. FlyoverDiscovery:");
        assertEq(
            discovery.lastProviderId(),
            0,
            "Initial provider ID should be 0"
        );
        console.log("   Last Provider ID:", discovery.lastProviderId());

        // Check PegInContract
        console.log("\n3. PegInContract:");
        assertEq(
            pegInContract.getMinPegIn(),
            cfg.minimumPegIn,
            "Min PegIn mismatch"
        );
        assertEq(
            pegInContract.dustThreshold(),
            cfg.dustThreshold,
            "Dust threshold mismatch"
        );
        console.log("   Min PegIn:", pegInContract.getMinPegIn());
        console.log("   Dust Threshold:", pegInContract.dustThreshold());
        console.log("   Version:", pegInContract.VERSION());

        // Check PegOutContract
        console.log("\n4. PegOutContract:");
        assertEq(
            pegOutContract.btcBlockTime(),
            cfg.btcBlockTime,
            "BTC block time mismatch"
        );
        assertEq(
            pegOutContract.dustThreshold(),
            cfg.dustThreshold,
            "Dust threshold mismatch"
        );
        console.log("   BTC Block Time:", pegOutContract.btcBlockTime());
        console.log("   Dust Threshold:", pegOutContract.dustThreshold());
        console.log("   Version:", pegOutContract.VERSION());

        console.log("\n[PASS] All contracts initialized correctly!");
    }

    function test_EndToEndProviderRegistration() public {
        console.log("\n=== TEST END-TO-END PROVIDER REGISTRATION ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        _deployAll(deployer, cfg);
        _assertAllProxyAdminsOwnedBy(deployer);

        // Setup roles
        bytes32 collateralAdderRole = collateralManagement.COLLATERAL_ADDER();
        collateralManagement.grantRole(collateralAdderRole, address(discovery));

        // Create a test provider
        address provider = makeAddr("provider");
        uint256 collateralAmount = cfg.minimumCollateral;
        vm.deal(provider, collateralAmount);

        console.log("1. Registering provider...");
        console.log("   Provider address:", provider);
        console.log("   Collateral amount:", collateralAmount);

        vm.prank(provider, provider);
        uint256 providerId = discovery.register{value: collateralAmount}(
            "Test Provider",
            "https://api.test.com",
            true,
            Flyover.ProviderType.PegIn
        );

        console.log("   Provider registered with ID:", providerId);
        assertEq(providerId, 1, "First provider should have ID 1");

        // Owner approval is required before collateral is forwarded and LP becomes operational
        discovery.approveRegistration(provider);

        // Verify collateral was added after approval
        console.log("\n2. Verifying collateral after approval...");
        uint256 pegInCollateral = collateralManagement.getPegInCollateral(
            provider
        );
        assertEq(
            pegInCollateral,
            collateralAmount,
            "Collateral should be recorded"
        );
        console.log("   PegIn Collateral:", pegInCollateral);

        // Verify provider is operational
        console.log("\n3. Checking operational status...");
        bool isOperational = discovery.isOperational(
            Flyover.ProviderType.PegIn,
            provider
        );
        assertTrue(isOperational, "Provider should be operational");
        console.log("   Is Operational:", isOperational);

        console.log("\n[PASS] End-to-end provider registration works!");
    }

    function test_AdminRolesGrantedToDeployer() public {
        console.log("\n=== TEST ADMIN ROLES GRANTED TO DEPLOYER ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        _deployAll(deployer, cfg);
        _assertAllProxyAdminsOwnedBy(deployer);

        bytes32 defaultAdminRole = collateralManagement.DEFAULT_ADMIN_ROLE();

        console.log(
            "Checking DEFAULT_ADMIN_ROLE for deployer on all contracts..."
        );

        assertTrue(
            collateralManagement.hasRole(defaultAdminRole, deployer),
            "CM: Deployer should have admin"
        );
        console.log("  CollateralManagement: true");

        assertTrue(
            discovery.hasRole(defaultAdminRole, deployer),
            "FD: Deployer should have admin"
        );
        console.log("  FlyoverDiscovery: true");

        assertTrue(
            pegInContract.hasRole(defaultAdminRole, deployer),
            "PI: Deployer should have admin"
        );
        console.log("  PegInContract: true");

        assertTrue(
            pegOutContract.hasRole(defaultAdminRole, deployer),
            "PO: Deployer should have admin"
        );
        console.log("  PegOutContract: true");

        console.log("\n[PASS] Deployer has admin role on all contracts!");
    }

    function test_ContractIsUpgradeable() public {
        console.log("\n=== CONTRACT IS UPGRADEABLE ===\n");

        HelperConfig.FlyoverConfig memory cfg = helperConfig.getFlyoverConfig();
        address deployer = address(this);

        _deployAll(deployer, cfg);

        address cmProxy = address(collateralManagement);
        ProxyAdmin proxyAdmin = ProxyAdmin(ProxyReader.readAdmin(vm, cmProxy));
        address newImplementation = address(new CollateralManagementContract());

        assertEq(
            ProxyReader.readImplementation(vm, cmProxy),
            collateralManagementImplementation,
            "Implementation mismatch"
        );
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(cmProxy),
            newImplementation,
            ""
        );
        assertEq(
            ProxyReader.readImplementation(vm, cmProxy),
            newImplementation,
            "Implementation mismatch"
        );

        address fdProxy = address(discovery);
        proxyAdmin = ProxyAdmin(ProxyReader.readAdmin(vm, fdProxy));
        newImplementation = address(new FlyoverDiscovery());
        assertEq(
            ProxyReader.readImplementation(vm, fdProxy),
            flyoverDiscoveryImplementation,
            "Implementation mismatch"
        );
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(fdProxy),
            newImplementation,
            ""
        );
        assertEq(
            ProxyReader.readImplementation(vm, fdProxy),
            newImplementation,
            "Implementation mismatch"
        );

        address piProxy = address(pegInContract);
        proxyAdmin = ProxyAdmin(ProxyReader.readAdmin(vm, piProxy));
        newImplementation = address(new PegInContract());
        assertEq(
            ProxyReader.readImplementation(vm, piProxy),
            pegInImplementation,
            "Implementation mismatch"
        );
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(piProxy),
            newImplementation,
            ""
        );
        assertEq(
            ProxyReader.readImplementation(vm, piProxy),
            newImplementation,
            "Implementation mismatch"
        );

        address poProxy = address(pegOutContract);
        proxyAdmin = ProxyAdmin(ProxyReader.readAdmin(vm, poProxy));
        newImplementation = address(new PegOutContract());
        assertEq(
            ProxyReader.readImplementation(vm, poProxy),
            pegOutImplementation,
            "Implementation mismatch"
        );
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(poProxy),
            newImplementation,
            ""
        );
        assertEq(
            ProxyReader.readImplementation(vm, poProxy),
            newImplementation,
            "Implementation mismatch"
        );

        proxyAdmin = ProxyAdmin(ProxyReader.readAdmin(vm, pauseRegistryProxy));
        newImplementation = address(new PauseRegistry());
        assertEq(
            ProxyReader.readImplementation(vm, pauseRegistryProxy),
            pauseRegistryImplementation,
            "Implementation mismatch"
        );
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(pauseRegistryProxy),
            newImplementation,
            ""
        );
        assertEq(
            ProxyReader.readImplementation(vm, pauseRegistryProxy),
            newImplementation,
            "Implementation mismatch"
        );

        console.log("\n[PASS] Contracts are upgradeable");
    }
}
