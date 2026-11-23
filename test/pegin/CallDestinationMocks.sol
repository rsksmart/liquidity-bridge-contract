// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/// @notice Records what the contract call delivered: the gas at entry, the value and the data
contract RecordingDestination {
    uint256 public gasAtEntry;
    uint256 public receivedValue;
    bytes public receivedData;
    uint256 public calls;

    fallback() external payable {
        _record(gasleft());
    }

    receive() external payable {
        _record(gasleft());
    }

    function _record(uint256 gasLeft) private {
        gasAtEntry = gasLeft;
        receivedValue = msg.value;
        receivedData = msg.data;
        calls += 1;
    }
}

/// @notice Always reverts
contract RevertingDestination {
    fallback() external payable {
        revert("destination refused");
    }
}

/// @notice Uses all the gas it receives
contract GasBurningDestination {
    fallback() external payable {
        // solhint-disable-next-line no-empty-blocks
        while (true) {}
    }
}

/// @notice Calls back into the peg-in contract during the call
contract ReentrantDestination {
    address public immutable target;

    constructor(address target_) {
        target = target_;
    }

    fallback() external payable {
        _reenter();
    }

    receive() external payable {
        _reenter();
    }

    function _reenter() private {
        (bool ok, bytes memory reason) = target.call(
            abi.encodeWithSignature("withdraw(uint256)", 1)
        );
        if (!ok) {
            // solhint-disable-next-line no-inline-assembly
            assembly {
                revert(add(reason, 0x20), mload(reason))
            }
        }
    }
}

/// @notice Succeeds and returns a large blob of data
contract LargeReturnDestination {
    fallback() external payable {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            return(0, 4096)
        }
    }
}
