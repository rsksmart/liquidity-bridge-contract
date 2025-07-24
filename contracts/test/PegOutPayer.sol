// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "../LiquidityBridgeContractV2.sol";
import "../QuotesV2.sol";

contract PegOutPayer {

    event Deposit(address indexed sender, uint256 amount);
    event PegOutPaid(QuotesV2.PegOutQuote quote, address indexed caller);
    event Withdraw(address indexed owner, uint256 amount);

    LiquidityBridgeContractV2 public immutable lbc;
    address public immutable owner;

    constructor(address payable _lbc) {
        lbc = LiquidityBridgeContractV2(_lbc);
        owner = msg.sender;
    }


    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    function executePegOut(QuotesV2.PegOutQuote memory quote, bytes memory signature) external {
        uint256 total = quote.value + quote.gasFee + quote.callFee + quote.productFeeAmount;
        require(total <= address(this).balance, "Insufficient balance in contract");
        emit PegOutPaid(quote, msg.sender);
        lbc.depositPegout{value: total}(quote, signature);
    }

    function withdraw(uint256 amount) external {
        require(msg.sender == owner, "Only owner can withdraw");
        require(amount <= address(this).balance, "Insufficient balance in contract");
        emit Withdraw(owner, amount);
        (bool sent, ) = payable(owner).call{value: amount}("");
        require(sent, "Failed to withdraw funds");
    }
}
