// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice A destination contract that records the call it received.
// solhint-disable comprehensive-interface
contract CallTarget {
    uint256 public received;
    bytes public lastData;
    bool public called;

    // solhint-disable-next-line no-complex-fallback
    fallback() external payable {
        called = true;
        received += msg.value;
        lastData = msg.data;
    }

    receive() external payable {
        called = true;
        received += msg.value;
    }
}

/// @notice A destination contract that always reverts.
// solhint-disable comprehensive-interface
contract RevertingTarget {
    // solhint-disable-next-line no-complex-fallback
    fallback() external payable {
        revert("nope");
    }

    receive() external payable {
        revert("nope");
    }
}
