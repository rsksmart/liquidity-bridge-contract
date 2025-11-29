// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/* solhint-disable comprehensive-interface */
/* solhint-disable avoid-low-level-calls */
contract ReentrancyCaller {

    bytes public data;
    bytes private _reason;

    event ReentrancyReverted(bytes reason);

    function reentrantCall() external payable {
       (bool success, bytes memory reason) = msg.sender.call(data);
        if (!success) {
            emit ReentrancyReverted(reason);
            _reason = reason;
        }
    }

    function setData(bytes calldata data_) external {
        data = data_;
    }

    function getRevertReason() external view returns (bytes memory) {
        return _reason;
    }
}
/* solhint-enable comprehensive-interface */
/* solhint-enable avoid-low-level-calls */
