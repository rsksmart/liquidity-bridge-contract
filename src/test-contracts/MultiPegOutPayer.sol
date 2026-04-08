// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IPegOut} from "../interfaces/IPegOut.sol";
import {Quotes} from "../libraries/Quotes.sol";

// solhint-disable comprehensive-interface
contract MultiPegOutPayer {
    IPegOut public immutable LBC;
    address public immutable OWNER;

    struct PegOutPayment {
        Quotes.PegOutQuote quote;
        bytes signature;
    }

    event Deposit(address indexed sender, uint256 indexed amount);
    event Withdraw(address indexed owner, uint256 indexed amount);

    error InsufficientBalance(uint256 balance, uint256 required);
    error NotOwner(address account);
    error SendError(bytes cause);

    constructor(address payable lbc_) {
        LBC = IPegOut(lbc_);
        OWNER = msg.sender;
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    /// @notice Pays for all N quotes in a single transaction, emitting N PegOutDeposit events.
    function executeMultiplePegOuts(PegOutPayment[] calldata payments) external {
        for (uint256 i = 0; i < payments.length; i++) {
            Quotes.PegOutQuote calldata q = payments[i].quote;
            uint256 total = q.value + q.gasFee + q.callFee;
            if (address(this).balance < total) {
                revert InsufficientBalance(address(this).balance, total);
            }
            LBC.depositPegOut{value: total}(q, payments[i].signature);
        }
    }

    function withdraw(uint256 amount) external {
        if (msg.sender != OWNER) revert NotOwner(msg.sender);
        if (address(this).balance < amount) revert InsufficientBalance(address(this).balance, amount);
        emit Withdraw(OWNER, amount);
        (bool sent, bytes memory cause) = payable(OWNER).call{value: amount}("");
        if (!sent) revert SendError(cause);
    }
}
