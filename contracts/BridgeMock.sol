// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./Bridge.sol";

contract BridgeMock is Bridge {

    mapping(bytes32 => uint256) private amounts;
    mapping(uint256 => bytes) private headers;
    mapping (bytes32 => bytes) private headersByHash;

    receive() external payable override {}
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
        uint256 amount = amounts[derivationArgumentsHash];
        amounts[derivationArgumentsHash] = 0;
        (bool success, ) = liquidityBridgeContractAddress.call{value: amount}("");
        require(success, "Sending funds failed");
        return int(amount);
    }

    function getBtcBlockchainBlockHeaderByHeight(uint256 height) external view override returns (bytes memory) {
        return headers[height];
    }

    function setPegin(bytes32 derivationArgumentsHash) public payable {
        amounts[derivationArgumentsHash] = msg.value;
    }

    function setHeader(uint256 height, bytes memory header) public {
        headers[height] = header;
    }

    function setHeaderByHash(bytes32 blockHash, bytes memory header) public {
        headersByHash[blockHash] = header;
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
    function registerBtcTransaction ( bytes calldata atx, int256 height, bytes calldata pmt ) external override {}
    function addSignature ( bytes calldata pubkey, bytes[] calldata signatures, bytes calldata txhash )
        external override {}
    function receiveHeaders ( bytes[] calldata blocks ) external override {}
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
    function updateCollections (  ) external override {}
    function getMinimumLockTxValue (  ) external pure override returns (int256) {return int256(2);}
    function getBtcTransactionConfirmations ( bytes32 , bytes32, uint256 , bytes32[] calldata  )
        external pure override returns (int256) {return int256(0);}
    function getLockingCap (  ) external pure override returns (int256) {return int256(0);}
    function increaseLockingCap ( int256 ) external pure override returns (bool) {return false;}
    function registerBtcCoinbaseTransaction ( bytes calldata btcTxSerialized, bytes32 blockHash, bytes
        calldata pmtSerialized, bytes32 witnessMerkleRoot, bytes32 witnessReservedValue ) external override {}
    function hasBtcBlockCoinbaseTransactionInformation ( bytes32  ) external pure override returns
        (bool) {return false;}
    function getActiveFederationCreationBlockHeight (  ) external pure override returns (uint256)
        {return uint256(0);}
    function getBtcBlockchainBestBlockHeader (  ) external pure override returns (bytes memory)
        {bytes memory b; return b;}

    function getBtcBlockchainBlockHeaderByHash(
        bytes32 blockHash
    ) external view override returns (bytes memory) {
        return headersByHash[blockHash];
    }

    function getBtcBlockchainParentBlockHeaderByHash ( bytes32) external pure override returns
        (bytes memory) {bytes memory b; return b;}
   
}
