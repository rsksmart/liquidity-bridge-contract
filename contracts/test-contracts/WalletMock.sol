// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;
// solhint-disable comprehensive-interface
contract WalletMock {

    bool private _rejectFunds;

    error PaymentRejected();

    receive() external payable {
        if (_rejectFunds) {
            revert PaymentRejected();
        }
    }

    function setRejectFunds(bool val) external {
        _rejectFunds = val;
    }
}
