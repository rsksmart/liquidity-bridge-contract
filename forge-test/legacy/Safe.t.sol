// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {LiquidityBridgeContract} from "../../contracts/legacy/LiquidityBridgeContract.sol";
import {LiquidityBridgeContractV2} from "../../contracts/legacy/LiquidityBridgeContractV2.sol";
import {GnosisSafe} from "../../contracts/test-contracts/safe-test-contracts/GnosisSafe.sol";
import {GnosisSafeProxyFactory} from "../../contracts/test-contracts/safe-test-contracts/proxies/GnosisSafeProxyFactory.sol";
import {GnosisSafeProxy} from "../../contracts/test-contracts/safe-test-contracts/proxies/GnosisSafeProxy.sol";
import {BridgeMock} from "../../contracts/test-contracts/BridgeMock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SafeTest is Test {
    GnosisSafe public safeSingleton;
    GnosisSafeProxyFactory public proxyFactory;

    address public signer1;
    address public signer2;

    uint256 constant LP_COLLATERAL = 1.5 ether;
    uint256 constant MIN_COLLATERAL_TEST = 0.03 ether;

    function setUp() public {
        // Create signers
        signer1 = address(this); // The test contract is signer1
        signer2 = makeAddr("signer2");
        vm.deal(signer2, 100 ether);

        // Deploy GnosisSafe singleton
        safeSingleton = new GnosisSafe();

        // Deploy GnosisSafeProxyFactory
        proxyFactory = new GnosisSafeProxyFactory();
    }

    function createTestWallet(
        address[] memory signers
    ) internal returns (GnosisSafe) {
        // Prepare initialization data for Safe
        bytes memory initializer = abi.encodeWithSelector(
            GnosisSafe.setup.selector,
            signers, // owners
            2, // threshold (2 of 2)
            address(0), // to
            hex"", // data
            address(0), // fallbackHandler
            address(0), // paymentToken
            0, // payment
            address(0) // paymentReceiver
        );

        // Create proxy
        GnosisSafeProxy proxy = proxyFactory.createProxy(
            address(safeSingleton),
            initializer
        );

        return GnosisSafe(payable(address(proxy)));
    }

    function test_ShouldCreateASafeWalletWithTwoSigners() public {
        address[] memory signers = new address[](2);
        signers[0] = signer1;
        signers[1] = signer2;

        GnosisSafe testSafeWallet = createTestWallet(signers);

        address[] memory owners = testSafeWallet.getOwners();
        assertEq(owners.length, 2, "Should have 2 owners");
        assertEq(owners[0], signer1, "First owner should be signer1");
        assertEq(owners[1], signer2, "Second owner should be signer2");
    }

    function test_ShouldChangeTheOwnershipOfLBC() public {
        address[] memory signers = new address[](2);
        signers[0] = signer1;
        signers[1] = signer2;

        GnosisSafe testSafeWallet = createTestWallet(signers);
        address safeAddress = address(testSafeWallet);

        // Deploy LBC V1
        BridgeMock bridgeMock = new BridgeMock();
        LiquidityBridgeContract lbcV1Impl = new LiquidityBridgeContract();

        bytes memory v1InitData = abi.encodeWithSelector(
            LiquidityBridgeContract.initialize.selector,
            payable(address(bridgeMock)),
            MIN_COLLATERAL_TEST,
            0.5 ether,
            uint32(50),
            uint32(60),
            uint256(2300 * 65164000),
            uint256(1),
            false
        );

        ERC1967Proxy lbcProxy = new ERC1967Proxy(
            address(lbcV1Impl),
            v1InitData
        );
        LiquidityBridgeContract lbc = LiquidityBridgeContract(
            payable(address(lbcProxy))
        );

        // Verify initialization
        assertEq(lbc.owner(), signer1, "Initial owner should be signer1");

        // Register an LP
        vm.prank(signer2, signer2);
        lbc.register{value: LP_COLLATERAL}(
            "First contract",
            "http://localhost/api",
            true,
            "both"
        );

        // Transfer ownership to Safe
        vm.prank(signer1);
        lbc.transferOwnership(safeAddress);

        // Verify ownership changed
        assertEq(lbc.owner(), safeAddress, "Owner should be Safe address");

        // Verify signer1 can no longer call owner functions
        vm.prank(signer1);
        vm.expectRevert("LBC005");
        lbc.setProviderStatus(1, true);

        // Note: In the TypeScript test, they also transfer proxy admin ownership
        // via upgrades.admin.transferProxyAdminOwnership, but that's Hardhat-specific
        // For this test, we're verifying the contract ownership transfer works
    }
}
