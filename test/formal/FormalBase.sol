// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {SymTest} from "halmos-cheatcodes/SymTest.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {PauseRegistry} from "../../src/PauseRegistry.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IPauseRegistry} from "../../src/interfaces/IPauseRegistry.sol";

/// @title Base contract for Halmos formal verification tests
/// @notice Deploys the CollateralManagement system behind an ERC1967 proxy,
///         grants COLLATERAL_ADDER and COLLATERAL_SLASHER roles, and exposes
///         the SymTest helpers for creating symbolic values.
abstract contract FormalBase is Test, SymTest {
    CollateralManagementContract public collateralManagement;
    PauseRegistry public pauseRegistry;

    address public owner;
    address public adder;
    address public slasher;

    uint48 constant ADMIN_DELAY = 0;
    uint256 constant MIN_COLLATERAL = 0.6 ether;
    uint256 constant RESIGN_DELAY = 500;
    uint256 constant REWARD_PERCENTAGE = 1000; // 10 % in basis points

    function setUp() public virtual {
        // block.number must be > 0: the contract uses resignationBlockNum == 0
        // as the sentinel for "not resigned", so block 0 would be ambiguous.
        vm.roll(1);

        owner = address(0x1);
        adder = address(0x2);
        slasher = address(0x3);

        vm.deal(owner, 1000 ether);
        vm.deal(adder, 1000 ether);
        vm.deal(slasher, 1000 ether);

        PauseRegistry prImpl = new PauseRegistry();
        ERC1967Proxy prProxy = new ERC1967Proxy(
            address(prImpl),
            abi.encodeCall(prImpl.initialize, (0, owner))
        );
        pauseRegistry = PauseRegistry(payable(address(prProxy)));

        CollateralManagementContract impl = new CollateralManagementContract();
        bytes memory initData = abi.encodeCall(
            impl.initialize,
            (
                owner,
                ADMIN_DELAY,
                MIN_COLLATERAL,
                RESIGN_DELAY,
                REWARD_PERCENTAGE,
                pauseRegistry
            )
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        collateralManagement = CollateralManagementContract(
            payable(address(proxy))
        );

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
    }
}
