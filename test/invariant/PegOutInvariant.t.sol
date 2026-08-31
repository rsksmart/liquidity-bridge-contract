// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {console} from "forge-std/Test.sol";
import {PegOutTestBase} from "../pegout/PegOutTestBase.sol";
import {PegOutHandler} from "./handlers/PegOutHandler.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";

/// @title PegOutContract Invariant Tests
/// @notice Tests critical invariants for the PegOutContract using a dedicated handler
contract PegOutInvariantTest is PegOutTestBase {
    PegOutHandler public handler;

    address public user;

    address[] public trackedAddresses;

    function setUp() public {
        deployPegOutContract();
        setupProviders();

        user = makeAddr("user");
        vm.deal(user, 100 ether);

        handler = new PegOutHandler(
            pegOutContract,
            collateralManagement,
            discovery,
            user
        );

        vm.prank(owner);
        pegOutContract.setPegOutEscrow(address(handler));

        handler.addLP(pegOutLp, pegOutLpKey, Flyover.ProviderType.PegOut);
        handler.addLP(fullLp, fullLpKey, Flyover.ProviderType.Both);

        trackedAddresses.push(pegOutLp);
        trackedAddresses.push(fullLp);
        trackedAddresses.push(user);

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = handler.depositPegOut.selector;
        selectors[1] = handler.refundUserPegOut.selector;
        selectors[2] = handler.lpWithdraw.selector;
        targetSelector(
            FuzzSelector({addr: address(handler), selectors: selectors})
        );
    }

    // ============ Invariant Tests ============

    /// @notice Contract balance must equal deposited minus refunded minus withdrawn
    /// @dev Deposited includes sub-dust overpayments retained by the contract
    function invariant_ContractSolvent() public view {
        uint256 deposited = handler.ghost_totalDeposited();
        uint256 refunded = handler.ghost_totalRefunded();
        uint256 withdrawn = handler.ghost_totalWithdrawn();

        if (deposited == 0) return;

        uint256 expected = deposited - refunded - withdrawn;
        assertEq(
            address(pegOutContract).balance,
            expected,
            "INVARIANT VIOLATED: Contract balance != deposited - refunded - withdrawn"
        );
    }

    /// @notice Contract balance must cover sum of all internal balances
    function invariant_BalanceSumConsistency() public view {
        uint256 totalInternalBalances = 0;
        for (uint256 i = 0; i < trackedAddresses.length; i++) {
            totalInternalBalances += pegOutContract.getBalance(
                trackedAddresses[i]
            );
        }

        assertGe(
            address(pegOutContract).balance,
            totalInternalBalances,
            "INVARIANT VIOLATED: Contract balance less than sum of internal balances"
        );
    }

    /// @notice No individual internal balance should exceed total deposited
    function invariant_NoUnderflow() public view {
        uint256 deposited = handler.ghost_totalDeposited();
        for (uint256 i = 0; i < trackedAddresses.length; i++) {
            uint256 balance = pegOutContract.getBalance(trackedAddresses[i]);
            assertLe(
                balance,
                deposited,
                "INVARIANT VIOLATED: Internal balance exceeds total deposited"
            );
        }
    }

    /// @notice Internal balances plus pending quote liability and retained dust must equal net deposits
    function invariant_InternalBalanceAccounting() public view {
        uint256 deposited = handler.ghost_totalDeposited();
        if (deposited == 0) return;

        uint256 refunded = handler.ghost_totalRefunded();
        uint256 withdrawn = handler.ghost_totalWithdrawn();

        uint256 totalInternalBalances = 0;
        for (uint256 i = 0; i < trackedAddresses.length; i++) {
            totalInternalBalances += pegOutContract.getBalance(
                trackedAddresses[i]
            );
        }

        uint256 pendingLiability = handler.calculateActiveLiability();
        uint256 retainedDust = handler.ghost_totalRetainedDust();
        assertEq(
            totalInternalBalances + pendingLiability + retainedDust,
            deposited - refunded - withdrawn,
            "INVARIANT VIOLATED: Internal balances + pending liability + retained dust != net deposits"
        );
    }

    /// @notice Rewards plus penalties in CM must equal total slash amount induced by peg-out refunds
    function invariant_SlashAccounting() public view {
        uint256 slashed = handler.ghost_totalSlashed();
        if (slashed == 0) return;

        uint256 rewards = collateralManagement.getRewards(user);
        uint256 penalties = collateralManagement.getPenalties();
        assertEq(
            rewards + penalties,
            slashed,
            "INVARIANT VIOLATED: Rewards + penalties != slashed"
        );
    }

    function invariant_callSummary() public view {
        console.log("\n--- PegOut Invariant Summary ---");
        console.log("Total deposited:", handler.ghost_totalDeposited());
        console.log("Total refunded:", handler.ghost_totalRefunded());
        console.log("Total withdrawn:", handler.ghost_totalWithdrawn());
        console.log("Retained sub-dust:", handler.ghost_totalRetainedDust());
        console.log("Active quotes:", handler.getActiveQuoteCount());
        console.log(
            "Handler depositPegOut calls:",
            handler.getHandlerCalls("depositPegOut")
        );
        console.log(
            "Handler refundUserPegOut calls:",
            handler.getHandlerCalls("refundUserPegOut")
        );
        console.log(
            "Handler lpWithdraw calls:",
            handler.getHandlerCalls("lpWithdraw")
        );
        console.log("Contract balance:", address(pegOutContract).balance);
        console.log("--------------------------------\n");
    }
}
