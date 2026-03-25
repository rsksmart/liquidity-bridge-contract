// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {console} from "forge-std/Test.sol";
import {PegInTestBase} from "../pegin/PegInTestBase.sol";
import {PegInHandler} from "./handlers/PegInHandler.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";

/// @title PegInContract Invariant Tests
/// @notice Tests critical invariants for the PegInContract using a dedicated handler
contract PegInInvariantTest is PegInTestBase {
    PegInHandler public handler;
    address public nonLpRefundCreditor;
    uint256 public baselineBalance;

    bytes constant RAW_TX_MOCK = hex"112233";
    bytes constant PMT_MOCK = hex"010203";
    uint256 constant HEIGHT_MOCK = 10;

    function setUp() public {
        deployPegInContract();
        setupProviders();

        handler = new PegInHandler(pegInContract);

        handler.addLP(pegInLp);
        handler.addLP(fullLp);
        address extraPegInLp = makeAddr("extraPegInLp");
        vm.deal(extraPegInLp, 100 ether);
        vm.prank(extraPegInLp, extraPegInLp);
        discovery.register{value: 0.6 ether}(
            "Extra PegIn Provider",
            "lp-extra.com",
            true,
            Flyover.ProviderType.PegIn
        );
        handler.addLP(extraPegInLp);

        (address creditor, ) = _seedNonLpRefundLiabilityFixture(
            fullLp,
            fullLpKey,
            1 ether,
            HEIGHT_MOCK,
            RAW_TX_MOCK,
            PMT_MOCK
        );
        nonLpRefundCreditor = creditor;
        baselineBalance = address(pegInContract).balance;

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = handler.deposit.selector;
        selectors[1] = handler.withdraw.selector;
        targetSelector(
            FuzzSelector({addr: address(handler), selectors: selectors})
        );
    }

    // ============ Invariant Tests ============

    /// @notice LP-only lower bound: contract balance must cover tracked LP internal balances
    function invariant_ContractSolvent() public view {
        uint256 totalLPBalances = handler.calculateTotalLPBalances();
        assertGe(
            address(pegInContract).balance,
            totalLPBalances,
            "INVARIANT VIOLATED: PegIn contract insolvent"
        );
    }

    /// @notice Contract balance must cover tracked LP liabilities plus seeded non-LP refund creditor
    function invariant_ContractSolventIncludingNonLpRefundCreditor()
        public
        view
    {
        uint256 totalLPBalances = handler.calculateTotalLPBalances();
        uint256 nonLpLiability = pegInContract.getBalance(nonLpRefundCreditor);
        assertGe(
            address(pegInContract).balance,
            totalLPBalances + nonLpLiability,
            "INVARIANT VIOLATED: PegIn contract insolvent with non-LP refund liability"
        );
    }

    /// @notice No individual LP balance should exceed total deposited through the handler
    function invariant_NoUnderflow() public view {
        uint256 deposited = handler.ghost_totalDeposited();
        uint256 count = handler.getLPCount();
        for (uint256 i = 0; i < count; i++) {
            uint256 balance = pegInContract.getBalance(handler.getLP(i));
            assertLe(
                balance,
                deposited,
                "INVARIANT VIOLATED: LP balance exceeds total deposited"
            );
        }
    }

    /// @notice Contract balance must equal deposited minus withdrawn (for deposit/withdraw handler actions)
    function invariant_GhostAccounting() public view {
        uint256 deposited = handler.ghost_totalDeposited();
        uint256 withdrawn = handler.ghost_totalWithdrawn();
        assertGe(
            address(pegInContract).balance,
            baselineBalance,
            "INVARIANT VIOLATED: Contract balance unexpectedly below baseline"
        );

        assertEq(
            address(pegInContract).balance - baselineBalance,
            deposited - withdrawn,
            "INVARIANT VIOLATED: Contract balance != deposited - withdrawn"
        );
    }

    function invariant_callSummary() public view {
        console.log("\n--- PegIn Invariant Summary ---");
        console.log("LPs tracked:", handler.getLPCount());
        console.log("Total deposited:", handler.ghost_totalDeposited());
        console.log("Total withdrawn:", handler.ghost_totalWithdrawn());
        console.log(
            "Handler deposit calls:",
            handler.getHandlerCalls("deposit")
        );
        console.log(
            "Handler withdraw calls:",
            handler.getHandlerCalls("withdraw")
        );
        console.log(
            "Seeded non-LP liability:",
            pegInContract.getBalance(nonLpRefundCreditor)
        );
        console.log("Baseline balance:", baselineBalance);
        console.log("Contract balance:", address(pegInContract).balance);
        console.log("-------------------------------\n");
    }
}
