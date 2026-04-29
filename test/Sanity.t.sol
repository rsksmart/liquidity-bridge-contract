// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

contract Sanity {
    function testAlwaysTrue() public pure {
        assert(true);
    }
}
