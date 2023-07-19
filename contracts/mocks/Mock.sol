// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "../liquidity-provider-contract/LiquidityProviderContract.sol";

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
        LiquidityProviderContract lbc = LiquidityProviderContract(lbcAddress);
        lbc.register{value: msg.value}(
            msg.sender,
            "First contract",
            10,
            7200,
            100,
            150,
            "http://localhost/api",
            true,
            "both"
        );
    }
}
