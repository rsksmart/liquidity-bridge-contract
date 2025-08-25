// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IPegIn} from "../interfaces/IPegIn.sol";

/* solhint-disable comprehensive-interface */
contract WithdrawReceiver {
    bool private _fail;
    IPegIn private _pegInContract;

    error SomeError();

    constructor(address pegInContract) {
        _fail = false;
        _pegInContract = IPegIn(pegInContract);
    }

    // solhint-disable-next-line no-complex-fallback
    receive() external payable {
        if (_fail) {
            revert SomeError();
        }
        _pegInContract.withdraw(0.005 ether);
    }

    function deposit() external payable {
        _pegInContract.deposit{ value: msg.value}();
    }

    function withdraw(uint256 amount) external {
        _pegInContract.withdraw(amount);
    }

    function setFail(bool fail) external {
        _fail = fail;
    }
}
/* solhint-enable comprehensive-interface */
