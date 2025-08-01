// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IPegOut} from "../interfaces/PegOut.sol";
import {Quotes} from "../libraries/Quotes.sol";


contract PegOutChangeReceiver {

    Quotes.PegOutQuote private _quote;
    bytes private _signature;
    bool private _fail;

    error SomeError();

    constructor() {
        _fail = false;
    }

    // solhint-disable-next-line
    receive() external payable {
        if (_fail) {
            revert SomeError();
        }
        IPegOut(msg.sender).depositPegOut{value: 0}(_quote, _signature);
    }

    // solhint-disable-next-line comprehensive-interface
    function setFail(bool fail) external {
        _fail = fail;
    }

    // solhint-disable-next-line comprehensive-interface
    function setPegOut(
        Quotes.PegOutQuote calldata quote,
        bytes calldata signature
    ) external {
        _quote = quote;
        _signature = signature;
    }
}
