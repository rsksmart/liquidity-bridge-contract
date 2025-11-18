// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInTestBase} from "./PegInTestBase.sol";
import {PegInContract} from "../../src/PegInContract.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Import the event
import "../../src/interfaces/ICollateralManagement.sol";

contract ConfigurationTest is PegInTestBase {
    address public notOwner;

    function setUp() public {
        deployPegInContract();

        notOwner = makeAddr("notOwner");
        vm.deal(notOwner, 100 ether);
    }

    // ============ receive function tests ============

    function test_Receive_RejectsPaymentsFromAddressesThatAreNotBridge()
        public
    {
        address payable contractAddress = payable(address(pegInContract));

        // Try sending from notOwner
        vm.prank(notOwner);
        vm.expectRevert(
            abi.encodeWithSelector(Flyover.PaymentNotAllowed.selector)
        );
        (bool success, ) = contractAddress.call{value: 1 ether}("");
        success; // Suppress warning

        // Try sending from owner
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(Flyover.PaymentNotAllowed.selector)
        );
        (success, ) = contractAddress.call{value: 1 ether}("");
        success; // Suppress warning
    }

    // ============ initialize function tests ============

    function test_Initialize_InitializesProperly() public view {
        // Check VERSION
        assertEq(pegInContract.VERSION(), "1.0.0", "VERSION should be 1.0.0");

        // Check dustThreshold
        assertEq(
            pegInContract.dustThreshold(),
            TEST_DUST_THRESHOLD,
            "dustThreshold should match"
        );

        // Check minPegIn
        assertEq(
            pegInContract.getMinPegIn(),
            TEST_MIN_PEGIN,
            "minPegIn should match"
        );

        // Check owner
        assertEq(pegInContract.owner(), owner, "owner should match");

        // Check feePercentage
        assertEq(
            pegInContract.getFeePercentage(),
            0,
            "feePercentage should be 0"
        );

        // Check feeCollector
        assertEq(
            pegInContract.getFeeCollector(),
            ZERO_ADDRESS,
            "feeCollector should be zero address"
        );

        // Check currentContribution
        assertEq(
            pegInContract.getCurrentContribution(),
            0,
            "currentContribution should be 0"
        );
    }

    function test_Initialize_AllowsInitializeOnlyOnce() public {
        vm.expectRevert(); // InvalidInitialization error
        pegInContract.initialize(
            owner,
            payable(address(bridgeMock)),
            TEST_DUST_THRESHOLD,
            TEST_MIN_PEGIN,
            address(collateralManagement),
            false,
            0,
            payable(ZERO_ADDRESS)
        );
    }

    function test_Initialize_RevertsIfNoCodeInCollateralManagement() public {
        address noCodeAddress = makeAddr("noCodeAddress");

        // Deploy a new PegInContract implementation
        PegInContract implementation = new PegInContract();

        bytes memory initData = abi.encodeCall(
            PegInContract.initialize,
            (
                owner,
                payable(address(bridgeMock)),
                TEST_DUST_THRESHOLD,
                TEST_MIN_PEGIN,
                noCodeAddress, // Address with no code
                false,
                0,
                payable(ZERO_ADDRESS)
            )
        );

        // Expect revert when deploying proxy
        vm.expectRevert(
            abi.encodeWithSelector(Flyover.NoContract.selector, noCodeAddress)
        );
        new ERC1967Proxy(address(implementation), initData);
    }

    // ============ setDustThreshold function tests ============

    function test_SetDustThreshold_OnlyAllowsOwnerToModify() public {
        vm.prank(notOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                notOwner
            )
        );
        pegInContract.setDustThreshold(1);
    }

    function test_SetDustThreshold_ModifiesProperly() public {
        uint256 newDustThreshold = 1;

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit PegInContract.DustThresholdSet(
            TEST_DUST_THRESHOLD,
            newDustThreshold
        );
        pegInContract.setDustThreshold(newDustThreshold);

        assertEq(
            pegInContract.dustThreshold(),
            newDustThreshold,
            "dustThreshold should be updated"
        );
    }

    // ============ setCollateralManagement function tests ============

    function test_SetCollateralManagement_OnlyAllowsOwnerToModify() public {
        // Deploy another CollateralManagement
        CollateralManagementContract otherCM = new CollateralManagementContract();
        bytes memory initData = abi.encodeCall(
            CollateralManagementContract.initialize,
            (
                owner,
                TEST_DEFAULT_ADMIN_DELAY,
                TEST_MIN_COLLATERAL,
                TEST_RESIGN_DELAY_BLOCKS,
                TEST_REWARD_PERCENTAGE
            )
        );
        ERC1967Proxy otherProxy = new ERC1967Proxy(address(otherCM), initData);
        address otherAddress = address(otherProxy);

        vm.prank(notOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                notOwner
            )
        );
        pegInContract.setCollateralManagement(otherAddress);
    }

    function test_SetCollateralManagement_RevertsIfAddressDoesNotHaveCode()
        public
    {
        address eoa = makeAddr("eoa");

        // Try with zero address
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(Flyover.NoContract.selector, ZERO_ADDRESS)
        );
        pegInContract.setCollateralManagement(ZERO_ADDRESS);

        // Try with EOA
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(Flyover.NoContract.selector, eoa)
        );
        pegInContract.setCollateralManagement(eoa);
    }

    function test_SetCollateralManagement_ModifiesProperly() public {
        // Deploy another CollateralManagement
        CollateralManagementContract otherCM = new CollateralManagementContract();
        bytes memory initData = abi.encodeCall(
            CollateralManagementContract.initialize,
            (
                owner,
                TEST_DEFAULT_ADMIN_DELAY,
                TEST_MIN_COLLATERAL,
                TEST_RESIGN_DELAY_BLOCKS,
                TEST_REWARD_PERCENTAGE
            )
        );
        ERC1967Proxy otherProxy = new ERC1967Proxy(address(otherCM), initData);
        address otherAddress = address(otherProxy);
        address originalAddress = address(collateralManagement);

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit CollateralManagementSet(originalAddress, otherAddress);
        pegInContract.setCollateralManagement(otherAddress);
    }

    // ============ setMinPegIn function tests ============

    function test_SetMinPegIn_OnlyAllowsOwnerToModify() public {
        vm.prank(notOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                notOwner
            )
        );
        pegInContract.setMinPegIn(1);
    }

    function test_SetMinPegIn_ModifiesProperly() public {
        uint256 newMinPegIn = 1;

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit PegInContract.MinPegInSet(TEST_MIN_PEGIN, newMinPegIn);
        pegInContract.setMinPegIn(newMinPegIn);

        assertEq(
            pegInContract.getMinPegIn(),
            newMinPegIn,
            "minPegIn should be updated"
        );
    }
}
