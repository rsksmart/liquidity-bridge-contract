// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IBridge} from "../../src/interfaces/IBridge.sol";

/// @title RegistryBridgeMock
/// @notice Standalone IBridge mock for the PegInAddressRegistry tests. Mirrors the shared
/// BridgeMock but makes getActivePowpegRedeemScript settable so a test can simulate a
/// federation (powpeg) composition change (the shared mock's version is `pure`). Deposits
/// are keyed by the derivationArgumentsHash via setPegin, matching the real fast-bridge path.
// solhint-disable comprehensive-interface
contract RegistryBridgeMock is IBridge {
    mapping(bytes32 => uint256) private _amounts;
    int256 private _registerError;
    bytes private _redeemScript;
    // Confirmations the bridge VIEW reports for any tx. Defaults to 6 (enough to gate a
    // registration); a test can force an insufficient count (0) or a negative error code.
    int256 private _confirmations = 6;

    constructor() {
        // Default: the same redeem script the shared BridgeMock returns, so off-chain
        // derivation vectors stay valid against this mock.
        _redeemScript = abi.encodePacked(
            hex"522102cd53fc53a07f211641a677d250f6de99caf620e8e77071e811a28b3bcddf0be1210362634ab5",
            hex"7dae9cb373a5d536e66a8c4f67468bbcfb063809bab643072d78a1242103c5946b3fbae03a654237da86",
            hex"3c9ed534e0878657175b132b8ca630f245df04db53ae"
        );
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable override {}

    function getActivePowpegRedeemScript() external view override returns (bytes memory) {
        return _redeemScript;
    }

    /// @notice Simulate a federation/powpeg composition change
    function setRedeemScript(bytes calldata redeemScript) external {
        _redeemScript = redeemScript;
    }

    /// @notice Records a proven deposit for a given derivation argument hash (with msg.value as amount)
    function setPegin(bytes32 derivationArgumentsHash) external payable {
        _amounts[derivationArgumentsHash] = msg.value;
    }

    /// @notice Forces a bridge error code from registerFastBridgeBtcTransaction
    function setPeginError(int256 errorCode) external {
        _registerError = errorCode;
    }

    /// @notice Sets the confirmation count the read-only getBtcTransactionConfirmations reports.
    /// Use a negative value to emulate an unknown tx/block (bridge error code).
    function setConfirmations(int256 confirmations) external {
        _confirmations = confirmations;
    }

    // solhint-disable-next-line gas-calldata-parameters
    function registerFastBridgeBtcTransaction(
        bytes memory,
        uint256,
        bytes memory,
        bytes32 derivationArgumentsHash,
        bytes memory,
        address payable,
        bytes memory,
        bool
    ) external override returns (int256) {
        if (_registerError != 0) {
            return _registerError;
        }
        uint256 amount = _amounts[derivationArgumentsHash];
        if (amount == 0) {
            // No proven deposit for this derivation: emulate a bridge validation failure.
            return int256(-303);
        }
        _amounts[derivationArgumentsHash] = 0;
        // Validate-only for the registry: the SPV-proven deposit amount is reported as the
        // positive return value. Unlike a peg-in LBC, the registry never custodies the funds,
        // so no ether is transferred to it here.
        return int256(amount);
    }

    // ---- Unused IBridge surface (no-op / zero stubs) ----
    // solhint-disable no-empty-blocks
    function registerBtcTransaction(bytes calldata, int256, bytes calldata) external override {}
    function addSignature(bytes calldata, bytes[] calldata, bytes calldata) external override {}
    function receiveHeaders(bytes[] calldata) external override {}
    function updateCollections() external override {}
    function registerBtcCoinbaseTransaction(
        bytes calldata, bytes32, bytes calldata, bytes32, bytes32
    ) external override {}
    // solhint-enable no-empty-blocks

    function receiveHeader(bytes calldata) external pure override returns (int256) { return 0; }
    function createFederation() external pure override returns (int256) { return 0; }
    function addFederatorPublicKey(bytes calldata) external pure override returns (int256) { return 0; }
    function addFederatorPublicKeyMultikey(bytes calldata, bytes calldata, bytes calldata)
        external pure override returns (int256) { return 0; }
    function commitFederation(bytes calldata) external pure override returns (int256) { return 0; }
    function rollbackFederation() external pure override returns (int256) { return 0; }
    function addLockWhitelistAddress(string calldata, int256) external pure override returns (int256) { return 0; }
    function addOneOffLockWhitelistAddress(string calldata, int256)
        external pure override returns (int256) { return 0; }
    function addUnlimitedLockWhitelistAddress(string calldata) external pure override returns (int256) { return 0; }
    function removeLockWhitelistAddress(string calldata) external pure override returns (int256) { return 0; }
    function setLockWhitelistDisableBlockDelay(int256) external pure override returns (int256) { return 0; }
    function voteFeePerKbChange(int256) external pure override returns (int256) { return 0; }
    function increaseLockingCap(int256) external pure override returns (bool) { return false; }
    function getBtcBlockchainBestChainHeight() external pure override returns (int) { return 0; }
    function getStateForBtcReleaseClient() external pure override returns (bytes memory) { return ""; }
    function getStateForDebugging() external pure override returns (bytes memory) { return ""; }
    function getBtcBlockchainInitialBlockHeight() external pure override returns (int) { return 0; }
    function getBtcBlockchainBlockHashAtDepth(int256) external pure override returns (bytes memory) { return ""; }
    function getBtcTxHashProcessedHeight(string calldata) external pure override returns (int64) { return 0; }
    function isBtcTxHashAlreadyProcessed(string calldata) external pure override returns (bool) { return false; }
    function getFederationAddress() external pure override returns (string memory) { return ""; }
    function getFederationSize() external pure override returns (int256) { return 0; }
    function getFederationThreshold() external pure override returns (int256) { return 0; }
    function getFederatorPublicKey(int256) external pure override returns (bytes memory) { return ""; }
    function getFederatorPublicKeyOfType(int256, string calldata)
        external pure override returns (bytes memory) { return ""; }
    function getFederationCreationTime() external pure override returns (int256) { return 0; }
    function getFederationCreationBlockNumber() external pure override returns (int256) { return 0; }
    function getRetiringFederationAddress() external pure override returns (string memory) { return ""; }
    function getRetiringFederationSize() external pure override returns (int256) { return 0; }
    function getRetiringFederationThreshold() external pure override returns (int256) { return 0; }
    function getRetiringFederatorPublicKey(int256) external pure override returns (bytes memory) { return ""; }
    function getRetiringFederatorPublicKeyOfType(int256, string calldata)
        external pure override returns (bytes memory) { return ""; }
    function getRetiringFederationCreationTime() external pure override returns (int256) { return 0; }
    function getRetiringFederationCreationBlockNumber() external pure override returns (int256) { return 0; }
    function getPendingFederationHash() external pure override returns (bytes memory) { return ""; }
    function getPendingFederationSize() external pure override returns (int256) { return 0; }
    function getPendingFederatorPublicKey(int256) external pure override returns (bytes memory) { return ""; }
    function getPendingFederatorPublicKeyOfType(int256, string calldata)
        external pure override returns (bytes memory) { return ""; }
    function getLockWhitelistSize() external pure override returns (int256) { return 0; }
    function getLockWhitelistAddress(int256) external pure override returns (string memory) { return ""; }
    function getLockWhitelistEntryByAddress(string calldata) external pure override returns (int256) { return 0; }
    function getFeePerKb() external pure override returns (int256) { return 0; }
    function getMinimumLockTxValue() external pure override returns (int256) { return 2; }
    function getBtcTransactionConfirmations(bytes32, bytes32, uint256, bytes32[] calldata)
        external view override returns (int256) { return _confirmations; }
    function getLockingCap() external pure override returns (int256) { return 0; }
    function hasBtcBlockCoinbaseTransactionInformation(bytes32) external pure override returns (bool) { return false; }
    function getActiveFederationCreationBlockHeight() external pure override returns (uint256) { return 0; }
    function getBtcBlockchainBestBlockHeader() external pure override returns (bytes memory) { return ""; }
    function getBtcBlockchainBlockHeaderByHash(bytes32) external pure override returns (bytes memory) { return ""; }
    function getBtcBlockchainBlockHeaderByHeight(uint256) external pure override returns (bytes memory) { return ""; }
    function getBtcBlockchainParentBlockHeaderByHash(bytes32) external pure override returns (bytes memory) { return ""; }
}
