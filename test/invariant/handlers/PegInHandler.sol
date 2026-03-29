// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {HandlerBase} from "./HandlerBase.sol";
import {PegInContract} from "../../../src/PegInContract.sol";

/// @title PegIn Invariant Handler
/// @notice Provides fuzzable handler functions for PegInContract invariant testing
contract PegInHandler is HandlerBase {
    PegInContract public pegInContract;

    address[] public trackedLPs;
    mapping(address => bool) public isTrackedLP;

    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalWithdrawn;

    constructor(PegInContract pegInContract_) {
        pegInContract = pegInContract_;
    }

    function addLP(address lp) external {
        if (!isTrackedLP[lp]) {
            trackedLPs.push(lp);
            isTrackedLP[lp] = true;
        }
    }

    function deposit(uint256 lpSeed, uint256 amount) external {
        handlerCalls["deposit"] += 1;
        amount = bound(amount, 0.01 ether, 10 ether);
        address lp = trackedLPs[lpSeed % trackedLPs.length];

        vm.deal(lp, amount);
        vm.prank(lp);
        try pegInContract.deposit{value: amount}() {
            ghost_totalDeposited += amount;
        } catch {}
    }

    function withdraw(uint256 lpSeed, uint256 amount) external {
        handlerCalls["withdraw"] += 1;
        address lp = trackedLPs[lpSeed % trackedLPs.length];
        uint256 balance = pegInContract.getBalance(lp);

        if (balance == 0) return;

        amount = bound(amount, 1, balance);

        vm.prank(lp);
        try pegInContract.withdraw(amount) {
            ghost_totalWithdrawn += amount;
        } catch {}
    }

    function getLPCount() external view returns (uint256) {
        return trackedLPs.length;
    }

    function getLP(uint256 idx) external view returns (address) {
        return trackedLPs[idx];
    }

    function calculateTotalLPBalances() external view returns (uint256 total) {
        for (uint256 i = 0; i < trackedLPs.length; i++) {
            total += pegInContract.getBalance(trackedLPs[i]);
        }
    }
}
