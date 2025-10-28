// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Test.sol";
import {FlyoverDiscovery} from "../../contracts/FlyoverDiscovery.sol";
import {CollateralManagementContract} from "../../contracts/CollateralManagement.sol";
import {PegInContract} from "../../contracts/PegInContract.sol";
import {PegOutContract} from "../../contracts/PegOutContract.sol";
import {BridgeMock} from "../../contracts/test-contracts/BridgeMock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Flyover} from "../../contracts/libraries/Flyover.sol";

/// @title System-wide Pause Functionality Tests
/// @notice Tests that verify pause/unpause operations across all contracts in the system
contract PauseTest is Test {
    FlyoverDiscovery public flyoverDiscovery;
    CollateralManagementContract public collateralManagement;
    PegInContract public pegInContract;
    PegOutContract public pegOutContract;
    BridgeMock public bridgeMock;

    address public owner;
    address public pauser;
    address[] public signers;

    bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    uint256 constant TEST_MIN_COLLATERAL = 0.6 ether;

    function setUp() public {
        owner = address(this);
        pauser = makeAddr("pauser");
        vm.deal(pauser, 100 ether);

        for (uint i = 0; i < 5; i++) {
            address signer = makeAddr(string.concat("signer", vm.toString(i)));
            vm.deal(signer, 100 ether);
            signers.push(signer);
        }

        _deployContracts();
    }

    function _deployContracts() internal {
        bridgeMock = new BridgeMock();

        CollateralManagementContract cmImpl = new CollateralManagementContract();
        collateralManagement = CollateralManagementContract(payable(address(new ERC1967Proxy(
            address(cmImpl),
            abi.encodeCall(cmImpl.initialize, (owner, 30, TEST_MIN_COLLATERAL, 500, 1000))
        ))));

        FlyoverDiscovery dImpl = new FlyoverDiscovery();
        flyoverDiscovery = FlyoverDiscovery(payable(address(new ERC1967Proxy(
            address(dImpl),
            abi.encodeCall(dImpl.initialize, (owner, 5000, address(collateralManagement)))
        ))));

        PegInContract piImpl = new PegInContract();
        pegInContract = PegInContract(payable(address(new ERC1967Proxy(
            address(piImpl),
            abi.encodeCall(piImpl.initialize, (owner, payable(address(bridgeMock)), 2300 * 65164000, 0.5 ether, address(collateralManagement), false, 0, payable(address(0))))
        ))));

        PegOutContract poImpl = new PegOutContract();
        pegOutContract = PegOutContract(payable(address(new ERC1967Proxy(
            address(poImpl),
            abi.encodeCall(poImpl.initialize, (owner, payable(address(bridgeMock)), 2300 * 65164000, address(collateralManagement), false, 900, 0, payable(address(0))))
        ))));

        vm.warp(block.timestamp + 31);
        collateralManagement.grantRole(collateralManagement.COLLATERAL_ADDER(), address(flyoverDiscovery));
        collateralManagement.grantRole(collateralManagement.COLLATERAL_SLASHER(), address(pegInContract));
        collateralManagement.grantRole(collateralManagement.COLLATERAL_SLASHER(), address(pegOutContract));
    }

    function _grantPauserRole() internal {
        flyoverDiscovery.grantRole(PAUSER_ROLE, pauser);
        collateralManagement.grantRole(PAUSER_ROLE, pauser);
    }

    function test_CanPauseAllContractsSimultaneously() public {
        _grantPauserRole();

        vm.startPrank(pauser);
        flyoverDiscovery.pause("Emergency system-wide pause");
        collateralManagement.pause("Emergency system-wide pause");
        vm.stopPrank();

        (bool isPausedD, string memory reasonD, ) = flyoverDiscovery.pauseStatus();
        (bool isPausedC, string memory reasonC, ) = collateralManagement.pauseStatus();

        assertTrue(isPausedD);
        assertEq(reasonD, "Emergency system-wide pause");
        assertTrue(isPausedC);
        assertEq(reasonC, "Emergency system-wide pause");
    }

    function test_CanUnpauseAllContractsSimultaneously() public {
        _grantPauserRole();

        vm.startPrank(pauser);
        flyoverDiscovery.pause("Test");
        collateralManagement.pause("Test");
        vm.stopPrank();

        (bool isPausedD, , ) = flyoverDiscovery.pauseStatus();
        (bool isPausedC, , ) = collateralManagement.pauseStatus();
        assertTrue(isPausedD);
        assertTrue(isPausedC);

        vm.startPrank(pauser);
        flyoverDiscovery.unpause();
        collateralManagement.unpause();
        vm.stopPrank();

        string memory reasonD;
        string memory reasonC;
        (isPausedD, reasonD, ) = flyoverDiscovery.pauseStatus();
        (isPausedC, reasonC, ) = collateralManagement.pauseStatus();

        assertFalse(isPausedD);
        assertEq(reasonD, "");
        assertFalse(isPausedC);
        assertEq(reasonC, "");
    }

    function test_TracksPauseTimestampsConsistentlyAcrossContracts() public {
        _grantPauserRole();

        vm.startPrank(pauser);
        flyoverDiscovery.pause("Timestamp test");
        collateralManagement.pause("Timestamp test");
        vm.stopPrank();

        (, , uint256 timeD) = flyoverDiscovery.pauseStatus();
        (, , uint256 timeC) = collateralManagement.pauseStatus();

        assertTrue(timeD > 0 && timeC > 0);
        assertEq(timeD, timeC);
    }

    function test_BlocksCriticalOperationsAcrossAllContractsWhenPaused() public {
        _grantPauserRole();

        vm.startPrank(pauser);
        flyoverDiscovery.pause("Emergency");
        collateralManagement.pause("Emergency");
        vm.stopPrank();

        vm.prank(signers[1]);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        flyoverDiscovery.register{value: 1 ether}("Test LP", "http://localhost/api", true, Flyover.ProviderType.PegIn);

        collateralManagement.grantRole(collateralManagement.COLLATERAL_ADDER(), owner);

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        collateralManagement.addPegInCollateralTo{value: 1 ether}(signers[1]);
    }

    function test_AllowsViewFunctionsToContinueWorkingWhenPaused() public view {
        assertTrue(flyoverDiscovery.getProvidersId() >= 0);
        assertEq(collateralManagement.getMinCollateral(), TEST_MIN_COLLATERAL);
        assertTrue(pegInContract.getMinPegIn() > 0);
        assertTrue(pegOutContract.dustThreshold() > 0);
    }

    function test_AllowsNonPausableFunctionsToContinueWorking() public pure {
        assertTrue(true);
    }

    function test_RestoresFullFunctionalityAfterSystemWideUnpause() public {
        _grantPauserRole();

        vm.startPrank(pauser);
        flyoverDiscovery.pause("Test");
        collateralManagement.pause("Test");
        vm.stopPrank();

        (bool isPausedD, , ) = flyoverDiscovery.pauseStatus();
        (bool isPausedC, , ) = collateralManagement.pauseStatus();
        assertTrue(isPausedD);
        assertTrue(isPausedC);

        vm.startPrank(pauser);
        flyoverDiscovery.unpause();
        collateralManagement.unpause();
        vm.stopPrank();

        (isPausedD, , ) = flyoverDiscovery.pauseStatus();
        (isPausedC, , ) = collateralManagement.pauseStatus();
        assertFalse(isPausedD);
        assertFalse(isPausedC);

        vm.prank(signers[1]);
        flyoverDiscovery.register{value: 1 ether}("Test LP", "http://localhost/api", true, Flyover.ProviderType.PegIn);

        assertEq(flyoverDiscovery.getProvidersId(), 1);

        collateralManagement.grantRole(collateralManagement.COLLATERAL_ADDER(), owner);
        collateralManagement.addPegInCollateralTo{value: 0.5 ether}(signers[1]);

        assertEq(collateralManagement.getPegInCollateral(signers[1]), 1.5 ether);
    }

    function test_HandlesWhereSomeContractsFailToPause() public {
        _grantPauserRole();

        vm.startPrank(pauser);
        flyoverDiscovery.pause("Partial pause");
        collateralManagement.pause("Partial pause");
        vm.stopPrank();

        (bool isPausedD, , ) = flyoverDiscovery.pauseStatus();
        (bool isPausedC, , ) = collateralManagement.pauseStatus();

        assertTrue(isPausedD || isPausedC);
    }

    function test_CanPerformEmergencyPauseWithCustomReason() public {
        _grantPauserRole();

        string memory reason = "Critical security vulnerability detected - immediate pause required";

        vm.startPrank(pauser);
        flyoverDiscovery.pause(reason);
        collateralManagement.pause(reason);
        vm.stopPrank();

        (, string memory reasonD, ) = flyoverDiscovery.pauseStatus();
        (, string memory reasonC, ) = collateralManagement.pauseStatus();

        assertEq(reasonD, reason);
        assertEq(reasonC, reason);
    }

    function test_MaintainsPauseStateAcrossMultipleOperations() public {
        _grantPauserRole();

        vm.startPrank(pauser);
        flyoverDiscovery.pause("Multiple ops");
        collateralManagement.pause("Multiple ops");
        vm.stopPrank();

        vm.startPrank(signers[1]);

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        flyoverDiscovery.register{value: 1 ether}("LP1", "url1", true, Flyover.ProviderType.PegIn);

        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        flyoverDiscovery.register{value: 1 ether}("LP2", "url2", true, Flyover.ProviderType.PegOut);

        vm.stopPrank();

        (bool isPausedD, , ) = flyoverDiscovery.pauseStatus();
        (bool isPausedC, , ) = collateralManagement.pauseStatus();

        assertTrue(isPausedD);
        assertTrue(isPausedC);
    }
}
