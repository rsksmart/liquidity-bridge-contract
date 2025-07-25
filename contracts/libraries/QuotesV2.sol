// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

library QuotesV2 {
    struct PegInQuote {
        uint256 callFee;
        uint256 penaltyFee;
        uint256 value;
        uint256 productFeeAmount;
        uint256 gasFee;
        bytes20 fedBtcAddress;
        address lbcAddress;
        address liquidityProviderRskAddress;
        address contractAddress;
        address payable rskRefundAddress;
        int64 nonce;
        uint32 gasLimit;
        uint32 agreementTimestamp;
        uint32 timeForDeposit;
        uint32 callTime;
        uint16 depositConfirmations;
        bool callOnRegister;
        bytes btcRefundAddress;
        bytes liquidityProviderBtcAddress;
        bytes data;
    }

    struct PegOutQuote {
        uint256 callFee;
        uint256 penaltyFee;
        uint256 value;
        uint256 productFeeAmount;
        uint256 gasFee;
        address lbcAddress;
        address lpRskAddress;
        address rskRefundAddress;
        int64   nonce;
        uint32  agreementTimestamp;
        uint32  depositDateLimit;
        uint32  transferTime;
        uint32  expireDate;
        uint32  expireBlock;
        uint16  depositConfirmations;
        uint16  transferConfirmations;
        bytes depositAddress;
        bytes btcRefundAddress;
        bytes lpBtcAddress;
    }

    error AmountTooLow(uint256 value, uint256 target);

    function checkAgreedAmount(
        PegInQuote calldata quote,
        uint transferredAmount
    ) external pure {
        uint agreedAmount = 0;
        agreedAmount = quote.value + quote.callFee + quote.productFeeAmount + quote.gasFee;


        uint delta = agreedAmount / 10000;
        // transferred amount should not be lower than (agreed amount - delta),
        // where delta is intended to tackle rounding problems
        if (agreedAmount - delta > transferredAmount) {
            revert AmountTooLow(transferredAmount, agreedAmount - delta);
        }
    }

    function encodeQuote(
        PegInQuote calldata quote
    ) external pure returns (bytes memory) {
        // Encode in two parts because abi.encode cannot take more than 12 parameters due to stack depth limits.
        return abi.encode(_encodePart1(quote), _encodePart2(quote));
    }

    function encodePegOutQuote(
        PegOutQuote calldata quote
    ) external pure returns (bytes memory) {
        // Encode in two parts because abi.encode cannot take more than 12 parameters due to stack depth limits.
        return abi.encode(_encodePegOutPart1(quote), _encodePegOutPart2(quote));
    }

    function _encodePart1(
        PegInQuote calldata quote
    ) private pure returns (bytes memory) {
        return
            abi.encode(
                quote.fedBtcAddress,
                quote.lbcAddress,
                quote.liquidityProviderRskAddress,
                quote.btcRefundAddress,
                quote.rskRefundAddress,
                quote.liquidityProviderBtcAddress,
                quote.callFee,
                quote.penaltyFee,
                quote.contractAddress
            );
    }

    function _encodePart2(
        PegInQuote calldata quote
    ) private pure returns (bytes memory) {
        return
            abi.encode(
                quote.data,
                quote.gasLimit,
                quote.nonce,
                quote.value,
                quote.agreementTimestamp,
                quote.timeForDeposit,
                quote.callTime,
                quote.depositConfirmations,
                quote.callOnRegister,
                quote.productFeeAmount,
                quote.gasFee
            );
    }

    function _encodePegOutPart1(
        PegOutQuote calldata quote
    ) private pure returns (bytes memory) {
        return
            abi.encode(
                quote.lbcAddress,
                quote.lpRskAddress,
                quote.btcRefundAddress,
                quote.rskRefundAddress,
                quote.lpBtcAddress,
                quote.callFee,
                quote.penaltyFee,
                quote.nonce,
                quote.depositAddress
            );
    }

    function _encodePegOutPart2(
        PegOutQuote calldata quote
    ) private pure returns (bytes memory) {
        return
            abi.encode(
                quote.value,
                quote.agreementTimestamp,
                quote.depositDateLimit,
                quote.depositConfirmations,
                quote.transferConfirmations,
                quote.transferTime,
                quote.expireDate,
                quote.expireBlock,
                quote.productFeeAmount,
                quote.gasFee
            );
    }
}
