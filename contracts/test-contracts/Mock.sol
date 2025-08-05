// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ILegacyLiquidityBridgeContract as LiquidityBridgeContract} from "../interfaces/ILegacy.sol";

// solhint-disable comprehensive-interface
contract Mock {
    int private _status;
    uint256 public balance;

    error MockError();

    function set(int s) external payable {
        _status = s;
    }

    function callRegister(address payable lbcAddress) external payable {
        LiquidityBridgeContract lbc = LiquidityBridgeContract(lbcAddress);
        lbc.register{value: msg.value}(
            "First contract",
            "http://localhost/api",
            true,
            "both"
        );
    }

    function check() external view returns (int) {
        return _status;
    }

    function fail() external pure {
        revert MockError();
    }
}
