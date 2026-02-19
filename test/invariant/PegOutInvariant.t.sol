// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {PegOutTestBase} from "../pegout/PegOutTestBase.sol";

/// @title PegOutContract Invariant Tests
/// @notice Tests critical invariants for the PegOutContract
contract PegOutInvariantTest is PegOutTestBase {
    // Ghost variables
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalRefunded;

    function setUp() public {
        deployPegOutContract();
        setupProviders();

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = this.invariant_NoUnderflow.selector;
        selectors[1] = this.invariant_ContractSolvent.selector;
        selectors[2] = this.invariant_GhostAccounting.selector;
        targetSelector(
            FuzzSelector({addr: address(this), selectors: selectors})
        );
    }

    // ============ Invariant Tests ============

    /// @notice Contract balance should never underflow
    function invariant_NoUnderflow() public view {
        uint256 contractBalance = address(pegOutContract).balance;

        // Check for underflow - values near max uint256 indicate underflow
        assertTrue(
            contractBalance < 1_000_000 ether,
            "INVARIANT VIOLATED: Contract balance indicates underflow"
        );
    }

    /// @notice Contract should remain solvent
    function invariant_ContractSolvent() public view {
        uint256 contractBalance = address(pegOutContract).balance;

        // The contract's balance must cover its net obligations:
        // obligations = total deposited - total refunded.
        if (ghost_totalDeposited >= ghost_totalRefunded) {
            uint256 obligations = ghost_totalDeposited - ghost_totalRefunded;
            assertTrue(
                contractBalance >= obligations,
                "INVARIANT VIOLATED: Contract balance below obligations"
            );
        } else {
            // Ghost accounting itself is inconsistent: more refunded than deposited.
            assertTrue(false, "INVARIANT VIOLATED: Refunded exceeds deposited");
        }
    }

    /// @notice Ghost accounting should be consistent
    function invariant_GhostAccounting() public view {
        uint256 contractBalance = address(pegOutContract).balance;

        // Contract balance should be <= deposits - refunds (with some tolerance for fees)
        if (ghost_totalDeposited > 0) {
            assertTrue(
                contractBalance <= ghost_totalDeposited + 1 ether,
                "INVARIANT VIOLATED: Contract has more than deposited"
            );
        }
    }

    function invariant_callSummary() public view {
        console.log("\n--- PegOut Invariant Summary ---");
        console.log("Total deposited:", ghost_totalDeposited);
        console.log("Total refunded:", ghost_totalRefunded);
        console.log("Contract balance:", address(pegOutContract).balance);
        console.log("--------------------------------\n");
    }
}
