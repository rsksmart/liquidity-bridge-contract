// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IBridge} from "../../src/interfaces/IBridge.sol";

/// @title RegistryBridgeMock
/// @notice Standalone IBridge mock for PegInAddressRegistry tests.
// solhint-disable comprehensive-interface
contract RegistryBridgeMock is IBridge {
    bytes private _redeemScript;
    int256 private _confirmations = 6;
    uint256 public mutatingBridgeCallCount;

    constructor() {
        _redeemScript = abi.encodePacked(
            hex"522102cd53fc53a07f211641a677d250f6de99caf620e8e77071e811a28b3bcddf0be1210362634ab5",
            hex"7dae9cb373a5d536e66a8c4f67468bbcfb063809bab643072d78a1242103c5946b3fbae03a654237da86",
            hex"3c9ed534e0878657175b132b8ca630f245df04db53ae"
        );
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable override {}

    function getActivePowpegRedeemScript()
        external
        view
        override
        returns (bytes memory)
    {
        return _redeemScript;
    }

    function setRedeemScript(bytes calldata redeemScript) external {
        _redeemScript = redeemScript;
    }

    function setConfirmations(int256 confirmations) external {
        _confirmations = confirmations;
    }

    function registerBtcTransaction(
        bytes calldata,
        int256,
        bytes calldata
    ) external override {
        ++mutatingBridgeCallCount;
    }

    function addSignature(
        bytes calldata,
        bytes[] calldata,
        bytes calldata
    ) external override {}

    function receiveHeaders(bytes[] calldata) external override {}

    function updateCollections() external override {}

    function registerBtcCoinbaseTransaction(
        bytes calldata,
        bytes32,
        bytes calldata,
        bytes32,
        bytes32
    ) external override {}

    // solhint-enable no-empty-blocks

    function registerFastBridgeBtcTransaction(
        bytes memory,
        uint256,
        bytes memory,
        bytes32,
        bytes memory,
        address payable,
        bytes memory,
        bool
    ) external pure override returns (int256) {
        return 0;
    }

    function receiveHeader(
        bytes calldata
    ) external pure override returns (int256) {
        return 0;
    }

    function createFederation() external pure override returns (int256) {
        return 0;
    }

    function addFederatorPublicKey(
        bytes calldata
    ) external pure override returns (int256) {
        return 0;
    }

    function addFederatorPublicKeyMultikey(
        bytes calldata,
        bytes calldata,
        bytes calldata
    ) external pure override returns (int256) {
        return 0;
    }

    function commitFederation(
        bytes calldata
    ) external pure override returns (int256) {
        return 0;
    }

    function rollbackFederation() external pure override returns (int256) {
        return 0;
    }

    function addLockWhitelistAddress(
        string calldata,
        int256
    ) external pure override returns (int256) {
        return 0;
    }

    function addOneOffLockWhitelistAddress(
        string calldata,
        int256
    ) external pure override returns (int256) {
        return 0;
    }

    function addUnlimitedLockWhitelistAddress(
        string calldata
    ) external pure override returns (int256) {
        return 0;
    }

    function removeLockWhitelistAddress(
        string calldata
    ) external pure override returns (int256) {
        return 0;
    }

    function setLockWhitelistDisableBlockDelay(
        int256
    ) external pure override returns (int256) {
        return 0;
    }

    function voteFeePerKbChange(
        int256
    ) external pure override returns (int256) {
        return 0;
    }

    function increaseLockingCap(int256) external pure override returns (bool) {
        return false;
    }

    function getBtcBlockchainBestChainHeight()
        external
        pure
        override
        returns (int256)
    {
        return 0;
    }

    function getStateForBtcReleaseClient()
        external
        pure
        override
        returns (bytes memory)
    {
        return "";
    }

    function getStateForDebugging()
        external
        pure
        override
        returns (bytes memory)
    {
        return "";
    }

    function getBtcBlockchainInitialBlockHeight()
        external
        pure
        override
        returns (int256)
    {
        return 0;
    }

    function getBtcBlockchainBlockHashAtDepth(
        int256
    ) external pure override returns (bytes memory) {
        return "";
    }

    function getBtcTxHashProcessedHeight(
        string calldata
    ) external pure override returns (int64) {
        return 0;
    }

    function isBtcTxHashAlreadyProcessed(
        string calldata
    ) external pure override returns (bool) {
        return false;
    }

    function getFederationAddress()
        external
        pure
        override
        returns (string memory)
    {
        return "";
    }

    function getFederationSize() external pure override returns (int256) {
        return 0;
    }

    function getFederationThreshold() external pure override returns (int256) {
        return 0;
    }

    function getFederatorPublicKey(
        int256
    ) external pure override returns (bytes memory) {
        return "";
    }

    function getFederatorPublicKeyOfType(
        int256,
        string calldata
    ) external pure override returns (bytes memory) {
        return "";
    }

    function getFederationCreationTime()
        external
        pure
        override
        returns (int256)
    {
        return 0;
    }

    function getFederationCreationBlockNumber()
        external
        pure
        override
        returns (int256)
    {
        return 0;
    }

    function getRetiringFederationAddress()
        external
        pure
        override
        returns (string memory)
    {
        return "";
    }

    function getRetiringFederationSize()
        external
        pure
        override
        returns (int256)
    {
        return 0;
    }

    function getRetiringFederationThreshold()
        external
        pure
        override
        returns (int256)
    {
        return 0;
    }

    function getRetiringFederatorPublicKey(
        int256
    ) external pure override returns (bytes memory) {
        return "";
    }

    function getRetiringFederatorPublicKeyOfType(
        int256,
        string calldata
    ) external pure override returns (bytes memory) {
        return "";
    }

    function getRetiringFederationCreationTime()
        external
        pure
        override
        returns (int256)
    {
        return 0;
    }

    function getRetiringFederationCreationBlockNumber()
        external
        pure
        override
        returns (int256)
    {
        return 0;
    }

    function getPendingFederationHash()
        external
        pure
        override
        returns (bytes memory)
    {
        return "";
    }

    function getPendingFederationSize()
        external
        pure
        override
        returns (int256)
    {
        return 0;
    }

    function getPendingFederatorPublicKey(
        int256
    ) external pure override returns (bytes memory) {
        return "";
    }

    function getPendingFederatorPublicKeyOfType(
        int256,
        string calldata
    ) external pure override returns (bytes memory) {
        return "";
    }

    function getLockWhitelistSize() external pure override returns (int256) {
        return 0;
    }

    function getLockWhitelistAddress(
        int256
    ) external pure override returns (string memory) {
        return "";
    }

    function getLockWhitelistEntryByAddress(
        string calldata
    ) external pure override returns (int256) {
        return 0;
    }

    function getFeePerKb() external pure override returns (int256) {
        return 0;
    }

    function getMinimumLockTxValue() external pure override returns (int256) {
        return 2;
    }

    function getBtcTransactionConfirmations(
        bytes32,
        bytes32,
        uint256,
        bytes32[] calldata
    ) external view override returns (int256) {
        return _confirmations;
    }

    function getLockingCap() external pure override returns (int256) {
        return 0;
    }

    function hasBtcBlockCoinbaseTransactionInformation(
        bytes32
    ) external pure override returns (bool) {
        return false;
    }

    function getActiveFederationCreationBlockHeight()
        external
        pure
        override
        returns (uint256)
    {
        return 0;
    }

    function getBtcBlockchainBestBlockHeader()
        external
        pure
        override
        returns (bytes memory)
    {
        return "";
    }

    function getBtcBlockchainBlockHeaderByHash(
        bytes32
    ) external pure override returns (bytes memory) {
        return "";
    }

    function getBtcBlockchainBlockHeaderByHeight(
        uint256
    ) external pure override returns (bytes memory) {
        return "";
    }

    function getBtcBlockchainParentBlockHeaderByHash(
        bytes32
    ) external pure override returns (bytes memory) {
        return "";
    }
}
