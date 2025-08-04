// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IBridge} from "../interfaces/IBridge.sol";

// solhint-disable comprehensive-interface
contract BridgeMock is IBridge {

    mapping(bytes32 => uint256) private _amounts;
    mapping(uint256 => bytes) private _headers;
    mapping (bytes32 => bytes) private _headersByHash;
    int private _confirmations;

    error SendFailed();

    constructor() {
        _confirmations = 2;
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable override {}

    // solhint-disable-next-line gas-calldata-parameters
    function registerFastBridgeBtcTransaction(
        bytes memory ,
        uint256 ,
        bytes memory,
        bytes32 derivationArgumentsHash,
        bytes memory,
        address payable liquidityBridgeContractAddress,
        bytes memory ,
        bool
    ) external override returns (int256) {
        uint256 amount = _amounts[derivationArgumentsHash];
        _amounts[derivationArgumentsHash] = 0;
        (bool success, ) = liquidityBridgeContractAddress.call{value: amount}("");
        if (!success) {
            revert SendFailed();
        }
        return int(amount);
    }

    function setConfirmations(int confirmations) external {
        _confirmations = confirmations;
    }

    // solhint-disable-next-line no-empty-blocks
    function registerBtcTransaction ( bytes calldata atx, int256 height, bytes calldata pmt ) external override {}
    function addSignature ( bytes calldata pubkey, bytes[] calldata signatures, bytes calldata txhash )
    // solhint-disable-next-line no-empty-blocks
        external override {}
    // solhint-disable-next-line no-empty-blocks
    function receiveHeaders ( bytes[] calldata blocks ) external override {}
    // solhint-disable-next-line no-empty-blocks
    function updateCollections (  ) external override {}
    function registerBtcCoinbaseTransaction ( bytes calldata btcTxSerialized, bytes32 blockHash, bytes
    // solhint-disable-next-line no-empty-blocks
        calldata pmtSerialized, bytes32 witnessMerkleRoot, bytes32 witnessReservedValue ) external override {}

    function getBtcBlockchainBlockHeaderByHeight(uint256 height) external view override returns (bytes memory) {
        return _headers[height];
    }

    function getBtcBlockchainBlockHeaderByHash(
        bytes32 blockHash
    ) external view override returns (bytes memory) {
        return _headersByHash[blockHash];
    }

    function getBtcTransactionConfirmations ( bytes32 , bytes32, uint256 , bytes32[] calldata  )
        external view override returns (int256) { return _confirmations; }

    function getActivePowpegRedeemScript() external pure returns (bytes memory) {
        bytes memory part1 = hex"522102cd53fc53a07f211641a677d250f6de99caf620e8e77071e811a28b3bcddf0be1210362634ab5";
        bytes memory part2 = hex"7dae9cb373a5d536e66a8c4f67468bbcfb063809bab643072d78a1242103c5946b3fbae03a654237da86";
        bytes memory part3 = hex"3c9ed534e0878657175b132b8ca630f245df04db53ae";
        return abi.encodePacked(part1, part2, part3);
    }

    function getBtcBlockchainBestChainHeight (  ) external pure override returns (int) {return 0;}
    function getStateForBtcReleaseClient (  ) external pure override returns (bytes memory) {bytes memory b; return b;}
    function getStateForDebugging (  ) external pure override returns (bytes memory) {bytes memory b; return b;}
    function getBtcBlockchainInitialBlockHeight (  ) external pure override returns (int) {return int(0);}
    function getBtcBlockchainBlockHashAtDepth ( int256 ) external pure override returns
        (bytes memory) {bytes memory b; return b;}
    function getBtcTxHashProcessedHeight ( string calldata ) external pure override returns (int64) {return int64(0);}
    function isBtcTxHashAlreadyProcessed ( string calldata ) external pure override returns (bool) {return false;}
    function getFederationAddress (  ) external pure override returns (string memory)
        {return "2N5muMepJizJE1gR7FbHJU6CD18V3BpNF9p";} // regtest genesis fed addr

    function receiveHeader ( bytes calldata ) external pure override returns (int256) {return int256(0);}
    function getFederationSize (  ) external pure override returns (int256) {return int256(0);}
    function getFederationThreshold (  ) external pure override returns (int256) {return int256(0);}
    function getFederatorPublicKey ( int256 ) external pure override returns (bytes memory)
        {bytes memory b; return b;}
    function getFederatorPublicKeyOfType ( int256, string calldata ) external pure
        override returns (bytes memory) {bytes memory b; return b;}
    function getFederationCreationTime (  ) external pure override returns (int256) {return int256(0);}
    function getFederationCreationBlockNumber (  ) external pure override returns (int256) {return int256(0);}
    function getRetiringFederationAddress (  ) external pure override returns (string memory)  {return "";}
    function getRetiringFederationSize (  ) external override  pure returns (int256) {return int256(0);}
    function getRetiringFederationThreshold (  ) external override  pure returns (int256) {return int256(0);}
    function getRetiringFederatorPublicKey ( int256 ) external override  pure returns (bytes memory)
        {bytes memory b; return b;}
    function getRetiringFederatorPublicKeyOfType ( int256,string calldata ) external pure override
        returns (bytes memory) {bytes memory b; return b;}
    function getRetiringFederationCreationTime (  ) external pure override returns (int256) {return int256(0);}
    function getRetiringFederationCreationBlockNumber (  ) external override  pure returns
        (int256) {return int256(0);}
    function createFederation (  ) external pure override returns (int256) {return int256(0);}
    function addFederatorPublicKey ( bytes calldata ) external pure override returns (int256)
        {return int256(0);}
    function addFederatorPublicKeyMultikey ( bytes calldata , bytes calldata , bytes calldata  )
        external pure override returns (int256) {return int256(0);}
    function commitFederation ( bytes calldata ) external pure override returns (int256) {return int256(0);}
    function rollbackFederation (  ) external pure override returns (int256) {return int256(0);}
    function getPendingFederationHash (  ) external pure override returns (bytes memory) {bytes memory b; return b;}
    function getPendingFederationSize (  ) external pure override returns (int256) {return int256(0);}
    function getPendingFederatorPublicKey ( int256  ) external pure override returns (bytes memory)
        {bytes memory b; return b;}
    function getPendingFederatorPublicKeyOfType ( int256 , string calldata  ) external pure override
        returns (bytes memory) {bytes memory b; return b;}
    function getLockWhitelistSize (  ) external pure override returns (int256) {return int256(0);}
    function getLockWhitelistAddress ( int256  ) external pure override returns (string memory) {return "";}
    function getLockWhitelistEntryByAddress ( string calldata  ) external pure  override returns (int256)
        {return int256(0);}
    function addLockWhitelistAddress ( string calldata , int256  ) external pure override returns (int256)
        {return int256(0);}
    function addOneOffLockWhitelistAddress ( string calldata , int256  ) external pure override returns
        (int256) {return int256(0);}
    function addUnlimitedLockWhitelistAddress ( string calldata  ) external pure override returns (int256)
        {return int256(0);}
    function removeLockWhitelistAddress ( string calldata  ) external pure override returns (int256)
        {return int256(0);}
    function setLockWhitelistDisableBlockDelay ( int256  ) external pure override returns (int256)
        {return int256(0);}
    function getFeePerKb (  ) external pure override returns (int256) {return int256(0);}
    function voteFeePerKbChange ( int256  ) external pure override returns (int256) {return int256(0);}
    function getMinimumLockTxValue (  ) external pure override returns (int256) {return int256(2);}
    function getLockingCap (  ) external pure override returns (int256) {return int256(0);}
    function increaseLockingCap ( int256 ) external pure override returns (bool) {return false;}
    function hasBtcBlockCoinbaseTransactionInformation ( bytes32  ) external pure override returns
        (bool) {return false;}
    function getActiveFederationCreationBlockHeight (  ) external pure override returns (uint256)
        {return uint256(0);}
    function getBtcBlockchainBestBlockHeader (  ) external pure override returns (bytes memory)
        {bytes memory b; return b;}

    function getBtcBlockchainParentBlockHeaderByHash ( bytes32) external pure override returns
        (bytes memory) {bytes memory b; return b;}

    function setHeader(uint256 height, bytes memory header) public {
        _headers[height] = header;
    }

    function setHeaderByHash(bytes32 blockHash, bytes memory header) public {
        _headersByHash[blockHash] = header;
    }

    function setPegin(bytes32 derivationArgumentsHash) public payable {
        _amounts[derivationArgumentsHash] = msg.value;
    }
}
