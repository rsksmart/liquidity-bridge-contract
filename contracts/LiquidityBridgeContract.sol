pragma solidity >=0.4.22 <0.8.0;

import "./Bridge.sol";

abstract contract LiquidityBridgeContract {

    Bridge bridge;

    constructor(address bridgeAddress) {
        bridge = Bridge(bridgeAddress);
    }

    function registerFastBridgeBtcTransaction(
        bytes memory btcRawTransaction, 
        bytes memory partialMerkleTree, 
        uint256 height, 
        bytes memory fedBtcAddress, 
        address LiquidityProviderRskAddress, 
        bytes memory userBtcRefundAddress, 
        bytes memory LiquidityProviderBtcAddress, 
        address callContract, 
        bytes memory callContractArguments, 
        int penaltyFee, 
        int successFee, 
        int gasLimit, 
        int nonce ,
        int valueToTransfer)
    public returns (int result) {
        bytes32 preHash = hash(fedBtcAddress, 
            LiquidityProviderRskAddress, 
            callContract, 
            callContractArguments, 
            penaltyFee, successFee, 
            gasLimit,
            nonce,
            valueToTransfer);
        bytes32 derivationHash = hash(preHash, userBtcRefundAddress, LiquidityProviderBtcAddress);

        uint amountToTransfer = validateData(derivationHash);

        int256 transferredAmount = bridge.registerBtcTransfer(
            btcRawTransaction, 
            height, 
            partialMerkleTree, 
            preHash, 
            userBtcRefundAddress, 
            address(this),
            LiquidityProviderBtcAddress, 
            amountToTransfer
        );

        if (transferredAmount > 0) {
            updateTransferredAmount(derivationHash, uint(transferredAmount));
        }

        return transferredAmount;
    }

    function hash(
        bytes memory fedBtcAddress, 
        address LiquidityProviderRskAddres,
        address callContract, 
        bytes memory callContractArguments, 
        int penaltyFee, 
        int successFee, 
        int gasLimit, 
        int nonce ,
        int valueToTransfer
    ) internal pure returns (bytes32 derivationHash) {
        return keccak256(abi.encode(
            fedBtcAddress, 
            LiquidityProviderRskAddres, 
            callContract, 
            callContractArguments, 
            penaltyFee, successFee, 
            gasLimit,
            nonce,
            valueToTransfer
        ));
    }

    function hash(
        bytes32 preHash,
        bytes memory userBtcRefundAddress, 
        bytes memory LiquidityProviderBtcAddres
    ) internal view returns (bytes32 derivationHash) {
        return keccak256(abi.encode(
            preHash,
            userBtcRefundAddress,
            address(this),
            LiquidityProviderBtcAddres
        ));
    }

    function validateData(bytes32 derivationHash) internal virtual returns (uint remainder);

    function updateTransferredAmount(bytes32 derivationHash, uint256 transferredAmount) internal virtual;

}
