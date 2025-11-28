// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {LiquidityBridgeContract} from "../../src/legacy/LiquidityBridgeContract.sol";
import {LiquidityBridgeContractV2} from "../../src/legacy/LiquidityBridgeContractV2.sol";
import {BridgeMock} from "../../src/test-contracts/BridgeMock.sol";
import {Mock} from "../../src/test-contracts/Mock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RegistrationTest is Test {
    LiquidityBridgeContractV2 public lbc;
    BridgeMock public bridgeMock;
    Mock public mockContract;

    address public lbcOwner;
    address[] public accounts;

    uint256 constant LP_COLLATERAL = 1.5 ether;
    uint256 constant MIN_COLLATERAL_TEST = 0.03 ether;

    struct TestCase {
        string name;
        string url;
        bool status;
        string providerType;
        string expectedError;
    }

    function setUp() public {
        lbcOwner = address(this);

        // Create test accounts
        for (uint i = 0; i <= 16; i++) {
            address account = address(
                uint160(uint256(keccak256(abi.encodePacked("account", i))))
            );
            vm.deal(account, 100 ether);
            accounts.push(account);
        }

        // Deploy BridgeMock
        bridgeMock = new BridgeMock();

        // Deploy V1 then upgrade to V2
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

        LiquidityBridgeContractV2 lbcImpl = new LiquidityBridgeContractV2();
        bytes32 implSlot = bytes32(
            uint256(keccak256("eip1967.proxy.implementation")) - 1
        );
        vm.store(
            address(lbcProxy),
            implSlot,
            bytes32(uint256(uint160(address(lbcImpl))))
        );

        lbc = LiquidityBridgeContractV2(payable(address(lbcProxy)));

        // Deploy Mock contract
        mockContract = new Mock();
    }

    function test_RegisterLiquidityProviderSuccessfully() public {
        address lpAccount = accounts[0];

        uint256 previousCollateral = lbc.getCollateral(lpAccount);

        vm.prank(lpAccount, lpAccount); // Set both msg.sender and tx.origin
        vm.expectEmit(true, false, false, true);
        emit LiquidityBridgeContractV2.Register(1, lpAccount, LP_COLLATERAL);
        lbc.register{value: LP_COLLATERAL}(
            "First contract",
            "http://localhost/api",
            true,
            "both"
        );

        uint256 currentCollateral = lbc.getCollateral(lpAccount);

        // For "both" type, collateral is split 50/50 between pegin and pegout
        // So LP_COLLATERAL goes half to collateral, half to pegoutCollateral
        assertEq(
            2 * (currentCollateral - previousCollateral),
            LP_COLLATERAL,
            "Collateral should be half of deposited amount for 'both' type"
        );
    }

    function test_FailOnRegisterIfBadParameters() public {
        TestCase[3] memory cases = [
            TestCase("", "http://localhost/api", true, "both", "LBC010"),
            TestCase("First contract", "", true, "both", "LBC017"),
            TestCase(
                "First contract",
                "http://localhost/api",
                true,
                "",
                "LBC018"
            )
        ];

        for (uint i = 0; i < cases.length; i++) {
            TestCase memory testCase = cases[i];

            vm.prank(accounts[0], accounts[0]);
            vm.expectRevert(bytes(testCase.expectedError));
            lbc.register{value: LP_COLLATERAL}(
                testCase.name,
                testCase.url,
                testCase.status,
                testCase.providerType
            );
        }
    }

    function test_FailWhenLiquidityProviderIsAlreadyRegistered() public {
        address lpAccount = accounts[5];

        vm.startPrank(lpAccount, lpAccount);

        vm.expectEmit(true, false, false, true);
        emit LiquidityBridgeContractV2.Register(1, lpAccount, LP_COLLATERAL);
        lbc.register{value: LP_COLLATERAL}(
            "First contract",
            "http://localhost/api",
            true,
            "both"
        );

        // Try to register again
        vm.expectRevert("LBC070");
        lbc.register{value: LP_COLLATERAL}(
            "First contract",
            "http://localhost/api",
            true,
            "both"
        );

        vm.stopPrank();
    }

    function test_FailOnRegisterIfNotDepositTheMinimumCollateral() public {
        vm.prank(accounts[0], accounts[0]);
        vm.expectRevert("LBC008");
        lbc.register{value: 0}(
            "First contract",
            "http://localhost/api",
            true,
            "both"
        );
    }

    function test_NotRegisterLPWithNotEnoughCollateral() public {
        vm.prank(accounts[0], accounts[0]);
        vm.expectRevert("LBC008");
        lbc.register{value: MIN_COLLATERAL_TEST * 2 - 1}(
            "First contract",
            "http://localhost/api",
            true,
            "both"
        );
    }

    function test_FailToRegisterLiquidityProviderFromAContract() public {
        address lpSigner = accounts[9];
        address notLpSigner = accounts[8];

        // First register the LP account successfully as EOA
        vm.prank(lpSigner, lpSigner);
        lbc.register{value: LP_COLLATERAL}(
            "First contract",
            "http://localhost/api",
            true,
            "both"
        );

        // Try to register from Mock contract (should fail due to tx.origin != msg.sender)
        vm.prank(lpSigner);
        vm.expectRevert("LBC003");
        mockContract.callRegister{value: LP_COLLATERAL}(payable(address(lbc)));

        vm.prank(notLpSigner);
        vm.expectRevert("LBC003");
        mockContract.callRegister{value: LP_COLLATERAL}(payable(address(lbc)));
    }
}
