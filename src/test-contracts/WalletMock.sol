// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;
// solhint-disable comprehensive-interface
contract WalletMock {

    bool private _rejectFunds;

    event TransactionRejected(address indexed to, uint256 indexed value, bytes reason);
    error PaymentRejected();

    receive() external payable {
        if (_rejectFunds) {
            revert PaymentRejected();
        }
    }

    function execute(address to, uint256 value, bytes calldata data) external payable {
        (bool success, bytes memory reason) = to.call{value: value}(data);
        if (!success) emit TransactionRejected(to, value, reason);
    }

    function setRejectFunds(bool val) external {
        _rejectFunds = val;
    }
}
