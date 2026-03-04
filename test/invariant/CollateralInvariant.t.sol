// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {console} from "forge-std/Test.sol";
import {CollateralTestBase} from "../collateral/CollateralTestBase.sol";
import {CollateralHandler} from "./handlers/CollateralHandler.sol";

/// @title CollateralManagement Invariant Tests
/// @notice Tests critical invariants for the CollateralManagement contract
contract CollateralInvariantTest is CollateralTestBase {
    CollateralHandler public handler;
    address public punisher;

    function setUp() public {
        deployCollateralManagement();
        setupRoles();

        punisher = makeAddr("punisher");
        handler = new CollateralHandler(
            collateralManagement,
            adder,
            slasher,
            punisher
        );

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = handler.addPegInCollateral.selector;
        selectors[1] = handler.addPegOutCollateral.selector;
        selectors[2] = handler.slashPegIn.selector;
        selectors[3] = handler.slashPegOut.selector;
        selectors[4] = handler.resignAndWithdraw.selector;
        selectors[5] = handler.withdrawRewards.selector;
        targetSelector(
            FuzzSelector({addr: address(handler), selectors: selectors})
        );
    }

    // ============ Invariant Tests ============

    /// @notice Contract balance should always cover all collateral + rewards + penalties
    function invariant_ContractSolvent() public view {
        uint256 contractBalance = address(collateralManagement).balance;
        uint256 totalCollateral = _calculateTotalCollateral();
        uint256 totalRewards = _calculateTotalRewards();
        uint256 totalPenalties = collateralManagement.getPenalties();

        assertGe(
            contractBalance,
            totalCollateral + totalRewards + totalPenalties,
            "INVARIANT VIOLATED: Contract is insolvent"
        );
    }

    /// @notice Contract balance must equal added - withdrawn - rewardsWithdrawn (tight equality)
    function invariant_GhostAccountingConsistent() public view {
        if (handler.ghost_totalAdded() == 0) return;

        uint256 contractBalance = address(collateralManagement).balance;
        uint256 added = handler.ghost_totalAdded();
        uint256 withdrawn = handler.ghost_totalWithdrawn();
        uint256 rewardsWithdrawn = handler.ghost_totalRewardsWithdrawn();

        assertEq(
            contractBalance,
            added - withdrawn - rewardsWithdrawn,
            "INVARIANT VIOLATED: Contract balance != added - withdrawn - rewardsWithdrawn"
        );
    }

    /// @notice No provider collateral should exceed total added through handler
    function invariant_NoNegativeCollateral() public view {
        uint256 added = handler.ghost_totalAdded();
        uint256 count = handler.getProviderCount();
        for (uint256 i = 0; i < count; i++) {
            address provider = handler.getProvider(i);
            assertLe(
                collateralManagement.getPegInCollateral(provider),
                added,
                "INVARIANT VIOLATED: PegIn collateral exceeds total added"
            );
            assertLe(
                collateralManagement.getPegOutCollateral(provider),
                added,
                "INVARIANT VIOLATED: PegOut collateral exceeds total added"
            );
        }
    }

    /// @notice Rewards + penalties must equal total slashed
    function invariant_RewardsPlusPenaltiesEqualSlashed() public view {
        uint256 slashed = handler.ghost_totalSlashed();
        if (slashed == 0) return;

        uint256 totalRewards = _calculateTotalRewards() +
            handler.ghost_totalRewardsWithdrawn();
        uint256 totalPenalties = collateralManagement.getPenalties();

        assertEq(
            totalRewards + totalPenalties,
            slashed,
            "INVARIANT VIOLATED: Rewards + penalties != total slashed"
        );
    }

    /// @notice Sum of all collateral + penalties + rewards must equal added - withdrawn - rewardsWithdrawn
    function invariant_FullConservation() public view {
        if (handler.ghost_totalAdded() == 0) return;

        uint256 totalCollateral = _calculateTotalCollateral();
        uint256 rewards = _calculateTotalRewards();
        uint256 penalties = collateralManagement.getPenalties();
        uint256 added = handler.ghost_totalAdded();
        uint256 withdrawn = handler.ghost_totalWithdrawn();
        uint256 rewardsWithdrawn = handler.ghost_totalRewardsWithdrawn();

        assertEq(
            totalCollateral + rewards + penalties,
            added - withdrawn - rewardsWithdrawn,
            "INVARIANT VIOLATED: Conservation of value failed"
        );
    }

    // ============ Helper Functions ============

    function _calculateTotalCollateral() internal view returns (uint256 total) {
        uint256 count = handler.getProviderCount();
        for (uint256 i = 0; i < count; i++) {
            address provider = handler.getProvider(i);
            total += collateralManagement.getPegInCollateral(provider);
            total += collateralManagement.getPegOutCollateral(provider);
        }
    }

    function _calculateTotalRewards() internal view returns (uint256) {
        return collateralManagement.getRewards(punisher);
    }

    function invariant_callSummary() public view {
        console.log("\n--- Collateral Invariant Summary ---");
        console.log("Providers:", handler.getProviderCount());
        console.log("Total added:", handler.ghost_totalAdded());
        console.log("Total slashed:", handler.ghost_totalSlashed());
        console.log("Total withdrawn:", handler.ghost_totalWithdrawn());
        console.log(
            "Total rewards withdrawn:",
            handler.ghost_totalRewardsWithdrawn()
        );
        console.log("Contract balance:", address(collateralManagement).balance);
        console.log("------------------------------------\n");
    }
}
