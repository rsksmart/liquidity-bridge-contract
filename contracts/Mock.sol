// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;

contract Mock {

    int private status;
    uint256 balance;

    function set(int s) external payable {
        status = s;
    }

    function check() external view returns (int){
        return status;
    }

    function fail() external pure {
        require(false, "error");
    }
}
