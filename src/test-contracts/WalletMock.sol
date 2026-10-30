// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;
// solhint-disable comprehensive-interface
contract WalletMock {

    bool private _rejectFunds;
    bool private _countReceipts;
    uint256 private _receipts;

    event TransactionRejected(address indexed to, uint256 indexed value, bytes reason);
    error PaymentRejected();

    // solhint-disable-next-line no-complex-fallback
    receive() external payable {
        if (_rejectFunds) {
            revert PaymentRejected();
        }
        if (_countReceipts) {
            // A first storage write costs about 22k gas: more than a 2300-gas payment allows
            ++_receipts;
        }
    }

    function execute(address to, uint256 value, bytes calldata data) external payable {
        (bool success, bytes memory reason) = to.call{value: value}(data);
        if (!success) emit TransactionRejected(to, value, reason);
    }

    function setRejectFunds(bool val) external {
        _rejectFunds = val;
    }

    function setCountReceipts(bool val) external {
        _countReceipts = val;
    }
}
