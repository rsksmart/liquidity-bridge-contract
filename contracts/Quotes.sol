// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

library Quotes {
    struct PeginQuote {
        bytes20 fedBtcAddress;
        address lbcAddress;
        address liquidityProviderRskAddress;
        bytes btcRefundAddress;
        address payable rskRefundAddress;
        bytes liquidityProviderBtcAddress;
        uint256 callFee;
        uint256 penaltyFee;
        address contractAddress;
        bytes data;
        uint32 gasLimit;
        int64 nonce;
        uint256 value;
        uint32 agreementTimestamp;
        uint32 timeForDeposit;
        uint32 callTime;
        uint16 depositConfirmations;
        bool callOnRegister;
    }

    struct PegOutQuote {
        address lbcAddress;
        address lpRskAddress;
        bytes btcRefundAddress;
        address rskRefundAddress;
        bytes lpBtcAddress;
        uint256 callFee;
        uint256 penaltyFee;
        int64 nonce;
        bytes deposityAddress;
        uint256 value;
        uint32 agreementTimestamp;
        uint32 depositDateLimit;
        uint16 depositConfirmations;
        uint16 transferConfirmations;
        uint32 transferTime;
        uint32 expireDate;
        uint32 expireBlock;
    }

    function encodeQuote(
        PeginQuote memory quote
    ) external pure returns (bytes memory) {
        // Encode in two parts because abi.encode cannot take more than 12 parameters due to stack depth limits.
        return abi.encode(encodePart1(quote), encodePart2(quote));
    }

    function encodePegOutQuote(
        PegOutQuote memory quote
    ) external pure returns (bytes memory) {
        // Encode in two parts because abi.encode cannot take more than 12 parameters due to stack depth limits.
        return abi.encode(encodePegOutPart1(quote), encodePegOutPart2(quote));
    }

    function encodePart1(
        PeginQuote memory quote
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

    function encodePart2(
        PeginQuote memory quote
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
                quote.callOnRegister
            );
    }

    function encodePegOutPart1(
        PegOutQuote memory quote
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
                quote.deposityAddress
            );
    }

    function encodePegOutPart2(
        PegOutQuote memory quote
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
                quote.expireBlock
            );
    }

    function checkAgreedAmount(
        PeginQuote memory quote,
        uint transferredAmount
    ) external pure {
        uint agreedAmount = quote.value + quote.callFee;
        uint delta = agreedAmount / 10000;
        // transferred amount should not be lower than (agreed amount - delta),
        // where delta is intended to tackle rounding problems
        require(
            transferredAmount >= agreedAmount - delta,
            "LBC057"
        );
    }

}