// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {CollateralManagementContract} from "../../contracts/CollateralManagement.sol";
import {ICollateralManagement} from "../../contracts/interfaces/ICollateralManagement.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Flyover} from "../../contracts/libraries/Flyover.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract AdditionTest is Test {
    CollateralManagementContract public collateralManagement;

    address public owner;
    address public adder;
    address public slasher;

    // Registered accounts for testing
    address public registeredPegInAccount;
    address public notRegisteredAccount1;
    address public registeredPegOutAccount;
    address public notRegisteredAccount2;
    address public anotherAccount;

    // Test constants matching the TypeScript tests
    uint48 constant TEST_DEFAULT_ADMIN_DELAY = 30;
    uint256 constant TEST_MIN_COLLATERAL = 0.6 ether;
    uint256 constant TEST_RESIGN_DELAY_BLOCKS = 500;
    uint256 constant TEST_REWARD_PERCENTAGE = 1000;

    uint256 constant ONE_RBTC = 1 ether;

    function setUp() public {
        // Create test accounts
        owner = makeAddr("owner");
        adder = makeAddr("adder");
        slasher = makeAddr("slasher");
        registeredPegInAccount = makeAddr("registeredPegInAccount");
        notRegisteredAccount1 = makeAddr("notRegisteredAccount1");
        registeredPegOutAccount = makeAddr("registeredPegOutAccount");
        notRegisteredAccount2 = makeAddr("notRegisteredAccount2");
        anotherAccount = makeAddr("anotherAccount");

        // Fund accounts
        vm.deal(owner, 100 ether);
        vm.deal(adder, 100 ether);
        vm.deal(registeredPegInAccount, 100 ether);
        vm.deal(notRegisteredAccount1, 100 ether);
        vm.deal(registeredPegOutAccount, 100 ether);
        vm.deal(notRegisteredAccount2, 100 ether);

        // Deploy implementation
        CollateralManagementContract implementation = new CollateralManagementContract();

        // Prepare initialization data
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

        // Deploy proxy
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        collateralManagement = CollateralManagementContract(
            payable(address(proxy))
        );

        // Grant roles
        vm.startPrank(owner);
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_ADDER(),
            adder
        );
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_SLASHER(),
            slasher
        );
        vm.stopPrank();

        // Register accounts by having adder add collateral to them
        vm.startPrank(adder);
        collateralManagement.addPegInCollateralTo{value: ONE_RBTC}(
            registeredPegInAccount
        );
        collateralManagement.addPegOutCollateralTo{value: ONE_RBTC}(
            registeredPegOutAccount
        );
        vm.stopPrank();
    }

    // Test: addPegInCollateral - only registered accounts can add collateral
    function test_AddPegInCollateral_OnlyAllowsRegisteredAccounts() public {
        // Adder can add collateral to registered accounts
        vm.prank(adder);
        collateralManagement.addPegInCollateralTo{value: ONE_RBTC}(
            registeredPegInAccount
        );

        // Not registered account cannot add collateral to themselves
        vm.prank(notRegisteredAccount1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.ProviderNotRegistered.selector,
                notRegisteredAccount1
            )
        );
        collateralManagement.addPegInCollateral{value: ONE_RBTC}();

        // Adder (who is not registered) cannot add collateral to themselves
        vm.prank(adder);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.ProviderNotRegistered.selector,
                adder
            )
        );
        collateralManagement.addPegInCollateral{value: ONE_RBTC}();

        // Registered account can add collateral to themselves
        vm.prank(registeredPegInAccount);
        vm.expectEmit(true, true, false, true);
        emit ICollateralManagement.PegInCollateralAdded(
            registeredPegInAccount,
            ONE_RBTC
        );
        collateralManagement.addPegInCollateral{value: ONE_RBTC}();

        // Verify total collateral (initial 1 RBTC + 1 RBTC from adder + 1 RBTC from self)
        assertEq(
            collateralManagement.getPegInCollateral(registeredPegInAccount),
            ONE_RBTC * 3,
            "PegIn collateral should be 3 RBTC"
        );
    }

    // Test: addPegOutCollateral - only registered accounts can add collateral
    function test_AddPegOutCollateral_OnlyAllowsRegisteredAccounts() public {
        // Adder can add collateral to registered accounts
        vm.prank(adder);
        collateralManagement.addPegOutCollateralTo{value: ONE_RBTC}(
            registeredPegOutAccount
        );

        // Not registered account cannot add collateral to themselves
        vm.prank(notRegisteredAccount2);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.ProviderNotRegistered.selector,
                notRegisteredAccount2
            )
        );
        collateralManagement.addPegOutCollateral{value: ONE_RBTC}();

        // Adder (who is not registered) cannot add collateral to themselves
        vm.prank(adder);
        vm.expectRevert(
            abi.encodeWithSelector(
                Flyover.ProviderNotRegistered.selector,
                adder
            )
        );
        collateralManagement.addPegOutCollateral{value: ONE_RBTC}();

        // Registered account can add collateral to themselves
        vm.prank(registeredPegOutAccount);
        vm.expectEmit(true, true, false, true);
        emit ICollateralManagement.PegOutCollateralAdded(
            registeredPegOutAccount,
            ONE_RBTC
        );
        collateralManagement.addPegOutCollateral{value: ONE_RBTC}();

        // Verify total collateral (initial 1 RBTC + 1 RBTC from adder + 1 RBTC from self)
        assertEq(
            collateralManagement.getPegOutCollateral(registeredPegOutAccount),
            ONE_RBTC * 3,
            "PegOut collateral should be 3 RBTC"
        );
    }

    // Test: addPegInCollateralTo - only adder can add to other accounts
    function test_AddPegInCollateralTo_OnlyAdderCanAddToOtherAccounts() public {
        bytes32 adderRole = collateralManagement.COLLATERAL_ADDER();

        // Adder can add collateral to registered accounts
        vm.prank(adder);
        vm.expectEmit(true, true, false, true);
        emit ICollateralManagement.PegInCollateralAdded(
            registeredPegInAccount,
            ONE_RBTC
        );
        collateralManagement.addPegInCollateralTo{value: ONE_RBTC}(
            registeredPegInAccount
        );

        // Verify collateral was added
        assertEq(
            collateralManagement.getPegInCollateral(registeredPegInAccount),
            ONE_RBTC * 2,
            "PegIn collateral should be 2 RBTC"
        );

        // Not registered account cannot use addPegInCollateralTo
        vm.prank(notRegisteredAccount1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                notRegisteredAccount1,
                adderRole
            )
        );
        collateralManagement.addPegInCollateralTo{value: ONE_RBTC}(
            registeredPegInAccount
        );

        // Registered account cannot use addPegInCollateralTo (they don't have COLLATERAL_ADDER role)
        vm.prank(registeredPegInAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                registeredPegInAccount,
                adderRole
            )
        );
        collateralManagement.addPegInCollateralTo{value: ONE_RBTC}(
            registeredPegInAccount
        );
    }

    // Test: addPegOutCollateralTo - only adder can add to other accounts
    function test_AddPegOutCollateralTo_OnlyAdderCanAddToOtherAccounts()
        public
    {
        bytes32 adderRole = collateralManagement.COLLATERAL_ADDER();

        // Adder can add collateral to registered accounts
        vm.prank(adder);
        vm.expectEmit(true, true, false, true);
        emit ICollateralManagement.PegOutCollateralAdded(
            registeredPegOutAccount,
            ONE_RBTC
        );
        collateralManagement.addPegOutCollateralTo{value: ONE_RBTC}(
            registeredPegOutAccount
        );

        // Verify collateral was added
        assertEq(
            collateralManagement.getPegOutCollateral(registeredPegOutAccount),
            ONE_RBTC * 2,
            "PegOut collateral should be 2 RBTC"
        );

        // Not registered account cannot use addPegOutCollateralTo
        vm.prank(notRegisteredAccount1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                notRegisteredAccount1,
                adderRole
            )
        );
        collateralManagement.addPegOutCollateralTo{value: ONE_RBTC}(
            registeredPegOutAccount
        );

        // Registered account cannot use addPegOutCollateralTo (they don't have COLLATERAL_ADDER role)
        vm.prank(registeredPegOutAccount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                registeredPegOutAccount,
                adderRole
            )
        );
        collateralManagement.addPegOutCollateralTo{value: ONE_RBTC}(
            registeredPegOutAccount
        );
    }
}
