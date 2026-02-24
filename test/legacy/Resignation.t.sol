// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {LiquidityBridgeContract} from "../../src/legacy/LiquidityBridgeContract.sol";
import {LiquidityBridgeContractV2} from "../../src/legacy/LiquidityBridgeContractV2.sol";
import {BridgeMock} from "../../src/test-contracts/BridgeMock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ResignationTest is Test {
    LiquidityBridgeContractV2 public lbc;
    BridgeMock public bridgeMock;

    address public lbcOwner;
    address[] public accounts;

    struct LiquidityProviderInfo {
        address signer;
        uint256 collateral;
        string providerType;
    }

    LiquidityProviderInfo[] public liquidityProviders;

    uint256 constant LP_COLLATERAL = 1.5 ether;
    uint256 constant LP_BALANCE = 0.5 ether;
    uint256 constant MIN_COLLATERAL_TEST = 0.03 ether;

    function setUp() public {
        lbcOwner = address(this);

        // Create test accounts
        for (uint i = 1; i <= 16; i++) {
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

        // Register 3 LPs
        address lp1 = address(uint160(uint256(keccak256("lp1"))));
        address lp2 = address(uint160(uint256(keccak256("lp2"))));
        address lp3 = address(uint160(uint256(keccak256("lp3"))));

        vm.deal(lp1, 100 ether);
        vm.deal(lp2, 100 ether);
        vm.deal(lp3, 100 ether);

        vm.prank(lp1, lp1);
        lbc.register{value: LP_COLLATERAL}(
            "First LP",
            "http://localhost/api1",
            true,
            "both"
        );

        vm.prank(lp2, lp2);
        lbc.register{value: LP_COLLATERAL / 2}(
            "Second LP",
            "http://localhost/api2",
            true,
            "pegin"
        );

        vm.prank(lp3, lp3);
        lbc.register{value: LP_COLLATERAL / 2}(
            "Third LP",
            "http://localhost/api3",
            true,
            "pegout"
        );

        liquidityProviders.push(
            LiquidityProviderInfo(lp1, LP_COLLATERAL, "both")
        );
        liquidityProviders.push(
            LiquidityProviderInfo(lp2, LP_COLLATERAL / 2, "pegin")
        );
        liquidityProviders.push(
            LiquidityProviderInfo(lp3, LP_COLLATERAL / 2, "pegout")
        );
    }

    // ============ Happy Path Tests ============

    function test_ResignWhenLPIsBothPeginAndPegout() public {
        LiquidityProviderInfo memory lp = liquidityProviders[0];

        // Deposit some balance
        vm.prank(lp.signer);
        lbc.deposit{value: LP_BALANCE}();

        uint256 resignBlocks = lbc.getResignDelayBlocks();

        // Capture balances before resign
        uint256 lbcEthBalBefore = address(lbc).balance;

        // Resign
        vm.prank(lp.signer);
        lbc.resign();

        // Verify LBC balance unchanged after resign
        assertEq(
            address(lbc).balance,
            lbcEthBalBefore,
            "LBC balance should not change on resign"
        );

        // Withdraw protocol balance
        uint256 lpEthBefore = lp.signer.balance;
        uint256 lpProtocolBalBefore = lbc.getBalance(lp.signer);

        vm.prank(lp.signer);
        lbc.withdraw(LP_BALANCE);

        // Verify withdrawals
        assertEq(
            address(lbc).balance,
            lbcEthBalBefore - LP_BALANCE,
            "LBC balance should decrease"
        );
        assertTrue(
            lp.signer.balance > lpEthBefore,
            "LP ETH balance should increase"
        );
        assertEq(
            lbc.getBalance(lp.signer),
            lpProtocolBalBefore - LP_BALANCE,
            "LP protocol balance should decrease"
        );

        // Mine blocks to pass resign delay
        vm.roll(block.number + resignBlocks);

        // Withdraw collateral
        uint256 peginCollBefore = lbc.getCollateral(lp.signer);
        uint256 pegoutCollBefore = lbc.getPegoutCollateral(lp.signer);
        uint256 totalColl = peginCollBefore + pegoutCollBefore;

        lpEthBefore = lp.signer.balance;
        lbcEthBalBefore = address(lbc).balance;

        vm.prank(lp.signer);
        lbc.withdrawCollateral();

        // Verify collateral withdrawal
        assertTrue(
            lp.signer.balance > lpEthBefore,
            "LP should receive collateral"
        );
        assertEq(
            address(lbc).balance,
            lbcEthBalBefore - totalColl,
            "LBC should lose collateral"
        );
        assertEq(
            lbc.getCollateral(lp.signer),
            0,
            "Pegin collateral should be 0"
        );
        assertEq(
            lbc.getPegoutCollateral(lp.signer),
            0,
            "Pegout collateral should be 0"
        );

        // Verify collateral was half/half for "both" type
        assertEq(peginCollBefore, lp.collateral / 2);
        assertEq(pegoutCollBefore, lp.collateral / 2);
    }

    function test_ResignWhenLPIsPeginOnly() public {
        LiquidityProviderInfo memory lp = liquidityProviders[1];

        // Deposit some balance
        vm.prank(lp.signer);
        lbc.deposit{value: LP_BALANCE}();

        uint256 resignBlocks = lbc.getResignDelayBlocks();

        // Capture balances before resign
        uint256 lbcEthBalBefore = address(lbc).balance;

        // Resign
        vm.prank(lp.signer);
        lbc.resign();

        // Verify LBC balance unchanged after resign
        assertEq(address(lbc).balance, lbcEthBalBefore);

        // Withdraw protocol balance
        uint256 lpEthBefore = lp.signer.balance;
        uint256 lpProtocolBalBefore = lbc.getBalance(lp.signer);

        vm.prank(lp.signer);
        lbc.withdraw(LP_BALANCE);

        // Verify withdrawals
        assertEq(address(lbc).balance, lbcEthBalBefore - LP_BALANCE);
        assertTrue(lp.signer.balance > lpEthBefore);
        assertEq(lbc.getBalance(lp.signer), lpProtocolBalBefore - LP_BALANCE);

        // Mine blocks to pass resign delay
        vm.roll(block.number + resignBlocks);

        // Withdraw collateral
        uint256 peginCollBefore = lbc.getCollateral(lp.signer);
        uint256 pegoutCollBefore = lbc.getPegoutCollateral(lp.signer);

        lpEthBefore = lp.signer.balance;
        lbcEthBalBefore = address(lbc).balance;

        vm.prank(lp.signer);
        lbc.withdrawCollateral();

        // Verify collateral withdrawal
        assertTrue(lp.signer.balance > lpEthBefore);
        assertEq(address(lbc).balance, lbcEthBalBefore - lp.collateral);
        assertEq(lbc.getCollateral(lp.signer), 0);
        assertEq(lbc.getPegoutCollateral(lp.signer), 0);

        // Verify only pegin collateral existed
        assertEq(peginCollBefore, lp.collateral);
        assertEq(pegoutCollBefore, 0);
    }

    function test_ResignWhenLPIsPegoutOnly() public {
        LiquidityProviderInfo memory lp = liquidityProviders[2];

        uint256 resignBlocks = lbc.getResignDelayBlocks();

        // Capture balances before resign
        uint256 lbcEthBalBefore = address(lbc).balance;

        // Resign
        vm.prank(lp.signer);
        lbc.resign();

        // Verify LBC balance unchanged after resign
        assertEq(address(lbc).balance, lbcEthBalBefore);

        // Mine blocks to pass resign delay
        vm.roll(block.number + resignBlocks);

        // Withdraw collateral
        uint256 peginCollBefore = lbc.getCollateral(lp.signer);
        uint256 pegoutCollBefore = lbc.getPegoutCollateral(lp.signer);

        uint256 lpEthBefore = lp.signer.balance;
        lbcEthBalBefore = address(lbc).balance;

        vm.prank(lp.signer);
        lbc.withdrawCollateral();

        // Verify collateral withdrawal
        assertTrue(lp.signer.balance > lpEthBefore);
        assertEq(address(lbc).balance, lbcEthBalBefore - lp.collateral);
        assertEq(lbc.getCollateral(lp.signer), 0);
        assertEq(lbc.getPegoutCollateral(lp.signer), 0);

        // Verify only pegout collateral existed
        assertEq(peginCollBefore, 0);
        assertEq(pegoutCollBefore, lp.collateral);
    }

    // ============ Error Cases Tests ============

    function test_FailWhenLiquidityProviderTryToWithdrawCollateralWithoutResignBefore()
        public
    {
        LiquidityProviderInfo memory lp = liquidityProviders[0];

        vm.prank(lp.signer);
        vm.expectRevert("LBC021");
        lbc.withdrawCollateral();

        // Now resign and try after delay
        uint256 resignBlocks = lbc.getResignDelayBlocks();

        vm.prank(lp.signer);
        lbc.resign();

        vm.roll(block.number + resignBlocks);

        vm.prank(lp.signer);
        lbc.withdrawCollateral(); // Should succeed now
    }

    function test_FailWhenLPResignsTwoTimes() public {
        LiquidityProviderInfo memory lp = liquidityProviders[0];

        uint256 resignBlocks = lbc.getResignDelayBlocks();

        vm.prank(lp.signer);
        lbc.resign(); // First resign succeeds

        vm.prank(lp.signer);
        vm.expectRevert("LBC023");
        lbc.resign(); // Second resign fails

        vm.roll(block.number + resignBlocks);

        vm.prank(lp.signer);
        lbc.withdrawCollateral(); // Should succeed
    }

    function test_FailWhenLPIsNotRegistered() public {
        address notRegisteredLP = accounts[3];

        vm.prank(notRegisteredLP);
        vm.expectRevert("LBC001");
        lbc.resign();
    }
}
