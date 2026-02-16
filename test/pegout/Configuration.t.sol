// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegOutTestBase} from "./PegOutTestBase.sol";
import {PegOutContract} from "../../src/PegOutContract.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
// Import the event
import "../../src/interfaces/ICollateralManagement.sol";

contract ConfigurationTest is PegOutTestBase {
    address public notOwner;

    function setUp() public {
        deployPegOutContract();

        notOwner = makeAddr("notOwner");
        vm.deal(notOwner, 100 ether);
    }

    // ============ initialize function tests ============

    function test_Initialize_InitializesProperly() public view {
        // Check VERSION
        assertEq(pegOutContract.VERSION(), "1.0.0", "VERSION should be 1.0.0");

        // Check btcBlockTime
        assertEq(
            pegOutContract.btcBlockTime(),
            TEST_BTC_BLOCK_TIME,
            "btcBlockTime should match"
        );

        // Check dustThreshold
        assertEq(
            pegOutContract.dustThreshold(),
            TEST_DUST_THRESHOLD,
            "dustThreshold should match"
        );

        // Check owner
        assertEq(pegOutContract.owner(), owner, "owner should match");

        // Check feePercentage
        assertEq(
            pegOutContract.getFeePercentage(),
            0,
            "feePercentage should be 0"
        );

        // Check feeCollector
        assertEq(
            pegOutContract.getFeeCollector(),
            ZERO_ADDRESS,
            "feeCollector should be zero address"
        );

        // Check currentContribution
        assertEq(
            pegOutContract.getCurrentContribution(),
            0,
            "currentContribution should be 0"
        );
    }

    function test_Initialize_AllowsInitializeOnlyOnce() public {
        vm.expectRevert(); // InvalidInitialization error
        pegOutContract.initialize(
            owner,
            payable(address(bridgeMock)),
            TEST_DUST_THRESHOLD,
            address(collateralManagement),
            false,
            TEST_BTC_BLOCK_TIME,
            0,
            payable(ZERO_ADDRESS)
        );
    }

    function test_Initialize_RevertsWhenCalledOnImplementation() public {
        PegOutContract implementation = new PegOutContract();

        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        implementation.initialize(
            owner,
            payable(address(bridgeMock)),
            TEST_DUST_THRESHOLD,
            address(collateralManagement),
            false,
            TEST_BTC_BLOCK_TIME,
            0,
            payable(ZERO_ADDRESS)
        );
    }

    function test_Initialize_RevertsIfNoCodeInCollateralManagement() public {
        address noCodeAddress = makeAddr("noCodeAddress");

        // Deploy a new PegOutContract implementation
        PegOutContract implementation = new PegOutContract();

        bytes memory initData = abi.encodeCall(
            PegOutContract.initialize,
            (
                owner,
                payable(address(bridgeMock)),
                TEST_DUST_THRESHOLD,
                noCodeAddress, // Address with no code
                false,
                TEST_BTC_BLOCK_TIME,
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
        vm.startPrank(notOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                notOwner,
                pegOutContract.DEFAULT_ADMIN_ROLE()
            )
        );
        pegOutContract.setDustThreshold(1);
        vm.stopPrank();
    }

    function test_SetDustThreshold_ModifiesProperly() public {
        uint256 newDustThreshold = 1;

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit PegOutContract.DustThresholdSet(
            TEST_DUST_THRESHOLD,
            newDustThreshold
        );
        pegOutContract.setDustThreshold(newDustThreshold);

        assertEq(
            pegOutContract.dustThreshold(),
            newDustThreshold,
            "dustThreshold should be updated"
        );
    }

    // ============ setBtcBlockTime function tests ============

    function test_SetBtcBlockTime_OnlyAllowsOwnerToModify() public {
        vm.startPrank(notOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                notOwner,
                pegOutContract.DEFAULT_ADMIN_ROLE()
            )
        );
        pegOutContract.setBtcBlockTime(5);
        vm.stopPrank();
    }

    function test_SetBtcBlockTime_ModifiesProperly() public {
        uint256 newBtcBlockTime = 5;

        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit PegOutContract.BtcBlockTimeSet(
            TEST_BTC_BLOCK_TIME,
            newBtcBlockTime
        );
        pegOutContract.setBtcBlockTime(newBtcBlockTime);

        assertEq(
            pegOutContract.btcBlockTime(),
            newBtcBlockTime,
            "btcBlockTime should be updated"
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

        vm.startPrank(notOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                notOwner,
                pegOutContract.DEFAULT_ADMIN_ROLE()
            )
        );
        pegOutContract.setCollateralManagement(otherAddress);
        vm.stopPrank();
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
        pegOutContract.setCollateralManagement(ZERO_ADDRESS);

        // Try with EOA
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(Flyover.NoContract.selector, eoa)
        );
        pegOutContract.setCollateralManagement(eoa);
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
        pegOutContract.setCollateralManagement(otherAddress);
    }
}
