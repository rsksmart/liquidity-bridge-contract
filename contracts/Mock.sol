// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "./LiquidityBridgeContract.sol";

contract Mock {
    int private status;
    uint256 public balance;

    function set(int s) external payable {
        status = s;
    }

    function check() external view returns (int) {
        return status;
    }

    function fail() external pure {
        require(false, "error");
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
}
