// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IPegInCommitFirst} from "../interfaces/IPegInCommitFirst.sol";

/// @notice Malicious peg-in destination that re-enters requestPegIn on delivery.
/// @dev Mirrors the WithdrawReceiver test-contract pattern. On receiving the fronted RBTC it
/// calls requestPegIn again with a different btcTxHash (a fresh pegInId), so the re-entry is
/// blocked by the nonReentrant guard rather than trivially hitting the already-processed check.
/* solhint-disable comprehensive-interface */
contract RequestPegInReenterReceiver {
    IPegInCommitFirst private _pegIn;
    bool private _attack;
    bytes32 private _reenterBtcTxHash;

    constructor(address pegInContract) {
        _pegIn = IPegInCommitFirst(pegInContract);
    }

    receive() external payable {
        if (_attack) {
            _attack = false;
            _pegIn.requestPegIn(address(this), 1, _reenterBtcTxHash, "", bytes32(0), 0, new bytes32[](0));
        }
    }

    /// @notice Arms or disarms the re-entry, and sets the btcTxHash used for the re-entrant call
    function setAttack(bool attack, bytes32 reenterBtcTxHash) external {
        _attack = attack;
        _reenterBtcTxHash = reenterBtcTxHash;
    }
}
/* solhint-enable comprehensive-interface */
