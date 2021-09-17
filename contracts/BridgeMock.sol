// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "./Bridge.sol";

contract BridgeMock is Bridge {

    mapping(bytes32 => uint256) private amounts;
    mapping(uint256 => bytes) private headers;

    function registerFastBridgeBtcTransaction(
        bytes memory btcTxSerialized, 
        uint256 height, 
        bytes memory pmtSerialized, 
        bytes32 derivationArgumentsHash, 
        bytes memory userRefundBtcAddress, 
        address payable liquidityBridgeContractAddress,
        bytes memory liquidityProviderBtcAddress, 
        bool shouldTransferToContract
    ) external override returns (int256) {
        uint256 amount = amounts[derivationArgumentsHash];
        amounts[derivationArgumentsHash] = 0;
        liquidityBridgeContractAddress.call{value: amount}("");
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

    function getBtcBlockchainBestChainHeight (  ) external view override returns (int) {return 0;}
    function getStateForBtcReleaseClient (  ) external view override returns (bytes memory) {bytes memory b; return b;}
    function getStateForDebugging (  ) external view override returns (bytes memory) {bytes memory b; return b;}
    function getBtcBlockchainInitialBlockHeight (  ) external view override returns (int) {return int(0);}
    function getBtcBlockchainBlockHashAtDepth ( int256 depth ) external view override returns (bytes memory) {bytes memory b; return b;}
    function getBtcTxHashProcessedHeight ( string calldata hash ) external view override returns (int64) {return int64(0);}
    function isBtcTxHashAlreadyProcessed ( string calldata hash ) external view override returns (bool) {return false;}
    function getFederationAddress (  ) external view override returns (string memory) {return "";}
    function registerBtcTransaction ( bytes calldata atx, int256 height, bytes calldata pmt ) external override {}
    function addSignature ( bytes calldata pubkey, bytes[] calldata signatures, bytes calldata txhash ) external override {}
    function receiveHeaders ( bytes[] calldata blocks ) external override {}
    function receiveHeader ( bytes calldata ablock ) external override returns (int256) {return int256(0);}
    function getFederationSize (  ) external view override returns (int256) {return int256(0);}
    function getFederationThreshold (  ) external view override returns (int256) {return int256(0);}
    function getFederatorPublicKey ( int256 index ) external view override returns (bytes memory) {bytes memory b; return b;}
    function getFederatorPublicKeyOfType ( int256 index, string calldata atype ) external override returns (bytes memory) {bytes memory b; return b;}
    function getFederationCreationTime (  ) external view override returns (int256) {return int256(0);}
    function getFederationCreationBlockNumber (  ) external view override returns (int256) {return int256(0);}
    function getRetiringFederationAddress (  ) external view override returns (string memory)  {return "";}
    function getRetiringFederationSize (  ) external override  view returns (int256) {return int256(0);}
    function getRetiringFederationThreshold (  ) external override  view returns (int256) {return int256(0);}
    function getRetiringFederatorPublicKey ( int256 index ) external override  view returns (bytes memory) {bytes memory b; return b;}
    function getRetiringFederatorPublicKeyOfType ( int256 index,string calldata atype ) external view override returns (bytes memory) {bytes memory b; return b;}
    function getRetiringFederationCreationTime (  ) external view override returns (int256) {return int256(0);}
    function getRetiringFederationCreationBlockNumber (  ) external override  view returns (int256) {return int256(0);}
    function createFederation (  ) external override returns (int256) {return int256(0);}
    function addFederatorPublicKey ( bytes calldata  key ) external override returns (int256) {return int256(0);}
    function addFederatorPublicKeyMultikey ( bytes calldata btcKey, bytes calldata rskKey, bytes calldata mstKey ) external override returns (int256) {return int256(0);}
    function commitFederation ( bytes calldata hash ) external override returns (int256) {return int256(0);}
    function rollbackFederation (  ) external override returns (int256) {return int256(0);}
    function getPendingFederationHash (  ) external view override returns (bytes memory) {bytes memory b; return b;}
    function getPendingFederationSize (  ) external view override returns (int256) {return int256(0);}
    function getPendingFederatorPublicKey ( int256 index ) external view override returns (bytes memory) {bytes memory b; return b;}
    function getPendingFederatorPublicKeyOfType ( int256 index, string calldata atype ) external view override returns (bytes memory) {bytes memory b; return b;}
    function getLockWhitelistSize (  ) external view override returns (int256) {return int256(0);}
    function getLockWhitelistAddress ( int256 index ) external view override returns (string memory) {return "";}
    function getLockWhitelistEntryByAddress ( string calldata aaddress ) external view  override returns (int256) {return int256(0);}
    function addLockWhitelistAddress ( string calldata aaddress, int256 maxTransferValue ) external override returns (int256) {return int256(0);}
    function addOneOffLockWhitelistAddress ( string calldata aaddress, int256 maxTransferValue ) external override returns (int256) {return int256(0);}
    function addUnlimitedLockWhitelistAddress ( string calldata aaddress ) external override returns (int256) {return int256(0);} 
    function removeLockWhitelistAddress ( string calldata aaddress ) external override returns (int256) {return int256(0);}
    function setLockWhitelistDisableBlockDelay ( int256 disableDelay ) external override returns (int256) {return int256(0);}
    function getFeePerKb (  ) external view override returns (int256) {return int256(0);}
    function voteFeePerKbChange ( int256 feePerKb ) external override returns (int256) {return int256(0);}
    function updateCollections (  ) external override {}
    function getMinimumLockTxValue (  ) external view override returns (int256) {return int256(0);}
    function getBtcTransactionConfirmations ( bytes32  txHash, bytes32 blockHash, uint256 merkleBranchPath, bytes32[] calldata merkleBranchHashes ) external view override returns (int256) {return int256(0);}
    function getLockingCap (  ) external view override returns (int256) {return int256(0);}
    function increaseLockingCap ( int256 newLockingCap ) external override returns (bool) {return false;}
    function registerBtcCoinbaseTransaction ( bytes calldata btcTxSerialized, bytes32 blockHash, bytes calldata pmtSerialized, bytes32 witnessMerkleRoot, bytes32 witnessReservedValue ) external override {}
    function hasBtcBlockCoinbaseTransactionInformation ( bytes32 blockHash ) external override returns (bool) {return false;}
    function getActiveFederationCreationBlockHeight (  ) external view override returns (uint256) {return uint256(0);}
    function getBtcBlockchainBestBlockHeader (  ) external view override returns (bytes memory) {bytes memory b; return b;}
    function getBtcBlockchainBlockHeaderByHash ( bytes32 btcBlockHash ) external view override returns (bytes memory) {bytes memory b; return b;}
    function getBtcBlockchainParentBlockHeaderByHash ( bytes32 btcBlockHash ) external view override returns (bytes memory) {bytes memory b; return b;}
   
}
