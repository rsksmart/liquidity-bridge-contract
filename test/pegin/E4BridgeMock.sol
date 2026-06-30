// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {BridgeMock} from "../../src/test-contracts/BridgeMock.sol";

/// @title E4BridgeMock
/// @notice Bridge mock for the E4 claim-flow tests. Extends the shared BridgeMock and overrides
/// registerFastBridgeBtcTransaction so it can serve BOTH the registry (validate-only: no transfer)
/// and PegInContract.resolvePegIn (releases the deposited RBTC to the contract). Behaviour is keyed
/// on `shouldTransferToContract`: the registry calls with `false` (just proves the deposit), while
/// resolvePegIn calls with `true` (the deposit is released to the LBC). Inherits the confirmations
/// machinery (setConfirmations / getBtcTransactionConfirmations) from BridgeMock.
// solhint-disable comprehensive-interface
contract E4BridgeMock is BridgeMock {
    mapping(bytes32 => uint256) private _proven;
    int256 private _forcedError;
    uint256 private _settlementAmount;

    /// @notice Records a proven deposit for a derivation argument hash (msg.value = amount).
    function fund(bytes32 derivationArgumentsHash) external payable {
        _proven[derivationArgumentsHash] += msg.value;
    }

    /// @notice Forces a specific error code from registerFastBridgeBtcTransaction.
    function setForcedError(int256 errorCode) external {
        _forcedError = errorCode;
    }

    /// @notice Sets a fixed amount released per settlement (0 => release the whole proven balance).
    /// Lets one registration fund several independent settlements (one per BTC tx).
    function setSettlementAmount(uint256 amount) external {
        _settlementAmount = amount;
    }

    // solhint-disable-next-line gas-calldata-parameters
    function registerFastBridgeBtcTransaction(
        bytes memory,
        uint256,
        bytes memory,
        bytes32 derivationArgumentsHash,
        bytes memory,
        address payable liquidityBridgeContractAddress,
        bytes memory,
        bool shouldTransferToContract
    ) external override returns (int256) {
        if (_forcedError != 0) {
            return _forcedError;
        }
        uint256 proven = _proven[derivationArgumentsHash];
        if (proven == 0) {
            // No proven deposit: emulate the bridge unprocessable-tx validation error.
            return int256(-303);
        }
        // The amount released for this settlement: a fixed chunk if configured, else the whole pool.
        uint256 amount = _settlementAmount == 0 ? proven : _settlementAmount;
        if (amount > proven) {
            amount = proven;
        }
        if (shouldTransferToContract) {
            // Settlement path (resolvePegIn): release the funds to the LBC and deduct from the pool.
            _proven[derivationArgumentsHash] = proven - amount;
            (bool ok,) = liquidityBridgeContractAddress.call{value: amount}("");
            require(ok, "E4BridgeMock: transfer failed");
        }
        // Validate-only path (registry registration): leave the proven deposit in place so the
        // same BTC tx can later be settled by resolvePegIn.
        return int256(amount);
    }
}
