// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "forge-std/Script.sol";

contract ComputeStorageSlot is Script {
    function run() external view {
        bytes32 slotPauseRegistry = bytes32(
            uint256(
                keccak256(
                    abi.encode(
                        uint256(keccak256("rsk.flyover.PauseRegistry")) - 1
                    )
                )
            ) & ~uint256(0xff)
        );
        bytes32 slotEmergencyPause = bytes32(
            uint256(
                keccak256(
                    abi.encode(
                        uint256(keccak256("rsk.flyover.EmergencyPause")) - 1
                    )
                )
            ) & ~uint256(0xff)
        );
        console.logBytes32(slotPauseRegistry);
        console.logBytes32(slotEmergencyPause);
    }
}
