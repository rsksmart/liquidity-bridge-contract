// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

contract WalletMock {

    bool private rejectFunds;

    function setRejectFunds(bool val) external {
        rejectFunds = val;
    }

    receive() external payable {
        require(!rejectFunds, "rejected");
    }
}
