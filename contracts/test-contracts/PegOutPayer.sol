// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ILegacyLiquidityBridgeContract as LiquidityBridgeContractV2} from "../interfaces/ILegacy.sol";
import {QuotesV2} from "../legacy/QuotesV2.sol";

// solhint-disable comprehensive-interface
contract PegOutPayer {
    LiquidityBridgeContractV2 public immutable LBC;
    address public immutable OWNER;

    event Deposit(address indexed sender, uint256 indexed amount);
    event PegOutPaid(QuotesV2.PegOutQuote quote, address indexed caller);
    event Withdraw(address indexed owner, uint256 indexed amount);

    error InsufficientBalance(uint256 amount, uint256 required);
    error NotOwner(address account);
    error SendError(bytes cause);

    constructor(address payable lbc_) {
        LBC = LiquidityBridgeContractV2(lbc_);
        OWNER = msg.sender;
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    function executePegOut(QuotesV2.PegOutQuote calldata quote, bytes calldata signature) external {
        uint256 total = quote.value + quote.gasFee + quote.callFee + quote.productFeeAmount;
        if (address(this).balance < total) {
            revert InsufficientBalance(address(this).balance, total);
        }
        emit PegOutPaid(quote, msg.sender);
        LBC.depositPegout{value: total}(quote, signature);
    }

    function withdraw(uint256 amount) external {
        if (msg.sender != OWNER) {
            revert NotOwner(msg.sender);
        }
        if (address(this).balance < amount){
            revert InsufficientBalance(address(this).balance, amount);
        }
        emit Withdraw(OWNER, amount);
        (bool sent, bytes memory cause) = payable(OWNER).call{value: amount}("");
        if (!sent) {
            revert SendError(cause);
        }
    }
}
