pragma solidity >=0.4.22 <0.8.0;

interface Bridge {
    function registerBtcTransfer(
        bytes memory btcTxSerialized, 
        uint256 height, 
        bytes memory pmtSerialized, 
        bytes32 derivationArgumentsHash, 
        bytes memory userRefundBtcAddress, 
        address LiquidityBridgeContractAddress, // TODO: verify if we can use address instead of string (string is specified in rskip and rskj)
        bytes memory LiquidityProviderBtcAddress, 
        uint amountToTransfer
    ) external returns (int256 executionStatus);
}
