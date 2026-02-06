// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {PegInTestBase} from "../pegin/PegInTestBase.sol";

/// @title PegInContract Invariant Tests  
/// @notice Tests critical invariants for the PegInContract
contract PegInInvariantTest is PegInTestBase {
    
    // Ghost variables for tracking state
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalWithdrawn;
    
    // Track LPs
    address[] public trackedLPs;
    mapping(address => bool) public isTrackedLP;
    
    function setUp() public {
        deployPegInContract();
        setupProviders();
        
        // Track initial LPs
        _trackLP(pegInLp);
        _trackLP(pegOutLp);
        _trackLP(fullLp);
        
        // Target this contract for invariant testing
        targetContract(address(this));
        
        // Only target handler functions, not setUp
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = this.deposit.selector;
        selectors[1] = this.withdraw.selector;
        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));
    }
    
    // ============ Handler Functions ============
    
    function deposit(uint256 lpSeed, uint256 amount) external {
        amount = bound(amount, 0.01 ether, 10 ether);
        address lp = _getLP(lpSeed);
        
        vm.deal(lp, amount);
        vm.prank(lp);
        pegInContract.deposit{value: amount}();
        
        ghost_totalDeposited += amount;
    }
    
    function withdraw(uint256 lpSeed, uint256 amount) external {
        address lp = _getLP(lpSeed);
        uint256 balance = pegInContract.getBalance(lp);
        
        if (balance == 0) return;
        
        amount = bound(amount, 1, balance);
        
        vm.prank(lp);
        try pegInContract.withdraw(amount) {
            ghost_totalWithdrawn += amount;
        } catch {}
    }
    
    // ============ Invariant Tests ============
    
    /// @notice Contract balance should equal sum of LP balances + DAO contributions
    function invariant_ContractBalanceMatchesLPBalances() public view {
        uint256 contractBalance = address(pegInContract).balance;
        uint256 totalLPBalances = _calculateTotalLPBalances();
        uint256 daoContributions = pegInContract.getCurrentContribution();
        
        assertEq(
            contractBalance,
            totalLPBalances + daoContributions,
            "INVARIANT VIOLATED: Contract balance != LP balances + DAO"
        );
    }
    
    /// @notice No LP balance should indicate underflow
    function invariant_NoUnderflow() public view {
        for (uint256 i = 0; i < trackedLPs.length; i++) {
            uint256 balance = pegInContract.getBalance(trackedLPs[i]);
            assertTrue(
                balance < 1_000_000 ether,
                "INVARIANT VIOLATED: LP balance indicates underflow"
            );
        }
    }
    
    /// @notice Ghost accounting should be consistent (relaxed check)
    function invariant_GhostAccounting() public view {
        // If nothing has been deposited via our handlers, skip this check
        if (ghost_totalDeposited == 0) return;
        
        uint256 contractBalance = address(pegInContract).balance;
        
        // Contract balance should be reasonable - not more than we deposited
        // (This is a relaxed check since initial setup also adds funds)
        assertTrue(
            contractBalance <= ghost_totalDeposited + 100 ether, // allow for initial LP deposits
            "INVARIANT VIOLATED: Contract has way more than deposited"
        );
    }
    
    // ============ Helper Functions ============
    
    function _getLP(uint256 seed) internal view returns (address) {
        return trackedLPs[seed % trackedLPs.length];
    }
    
    function _trackLP(address lp) internal {
        if (!isTrackedLP[lp]) {
            trackedLPs.push(lp);
            isTrackedLP[lp] = true;
        }
    }
    
    function _calculateTotalLPBalances() internal view returns (uint256 total) {
        for (uint256 i = 0; i < trackedLPs.length; i++) {
            total += pegInContract.getBalance(trackedLPs[i]);
        }
    }
    
    function invariant_callSummary() public view {
        console.log("\n--- PegIn Invariant Summary ---");
        console.log("LPs tracked:", trackedLPs.length);
        console.log("Total deposited:", ghost_totalDeposited);
        console.log("Total withdrawn:", ghost_totalWithdrawn);
        console.log("Contract balance:", address(pegInContract).balance);
        console.log("DAO contributions:", pegInContract.getCurrentContribution());
        console.log("-------------------------------\n");
    }
}
