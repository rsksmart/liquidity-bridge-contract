// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

library Quotes {
    struct PegInQuote {
        uint256 callFee;
        uint256 penaltyFee;
        uint256 value;
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

    uint256 public constant SAT_TO_WEI_CONVERSION = 10**10;

    /// @notice The type hash of the PegInQuote struct for EIP712
    /// @dev Due to the number of fields present in the struct, we'll just use the hash of the quote and the
    /// address of the liquidity provider offering it to calculate the EIP712 hash. In this way we avoid issues
    /// with stack depth limits and future modifications to the type hash based on changes in the struct.
    /// @dev keccak256("PegInQuote(address liquidityProvider,bytes32 quoteHash)")
    bytes32 public constant PEG_IN_QUOTE_TYPE_HASH = 0x82b0b35cb5a2b2130657be6794570d328b06b7687bdff463bce4a0cc24a880a2;

    /// @notice The type hash of the PegOutQuote struct for EIP712
    /// @dev Due to the number of fields present in the struct, we'll just use the hash of the quote and the
    /// address of the liquidity provider offering it to calculate the EIP712 hash. In this way we avoid issues
    /// with stack depth limits and future modifications to the type hash based on changes in the struct.
    /// @dev keccak256("PegOutQuote(address liquidityProvider,bytes32 quoteHash)")
    bytes32 public constant PEG_OUT_QUOTE_TYPE_HASH =
        0x940deda477f28e6fd80f8307aea1edb500dbd4ee20815878162fec9001fab898;

    error AmountTooLow(uint256 value, uint256 target);

    function checkAgreedAmount(
        PegInQuote calldata quote,
        uint transferredAmount
    ) external pure {
        uint agreedAmount = 0;
        agreedAmount = quote.value + quote.callFee + quote.gasFee;

        // Adjust for rounding when converting from wei to sats and back
        // This protects users from precision issues when client apps don't round properly
        if (agreedAmount > SAT_TO_WEI_CONVERSION && (agreedAmount % SAT_TO_WEI_CONVERSION) != 0) {
            agreedAmount -= (agreedAmount % SAT_TO_WEI_CONVERSION);
        }

        // transferred amount should not be lower than agreed amount
        if (agreedAmount > transferredAmount) {
            revert AmountTooLow(transferredAmount, agreedAmount);
        }
    }

    /// @notice This function is used to get the hashStruct of a peg in quote using EIP712 specification
    /// @dev The hashStruct should be later combined with the domain separator to get the final hash
    /// @param quote The peg in quote to hash
    /// @return hashStruct The hash struct to be combined with the domain separator
    function hashPegInQuoteEIP712(
        PegInQuote calldata quote
    ) external pure returns (bytes32) {
        return keccak256(abi.encode(
            PEG_IN_QUOTE_TYPE_HASH,
            quote.liquidityProviderRskAddress,
            keccak256(abi.encode(_encodePart1(quote), _encodePart2(quote)))
        ));
    }

    /// @notice This function is used to get the hashStruct of a peg out quote using EIP712 specification
    /// @dev The hashStruct should be later combined with the domain separator to get the final hash
    /// @param quote The peg out quote to hash
    /// @return hashStruct The hash struct to be combined with the domain separator
    function hashPegOutQuoteEIP712(
        PegOutQuote calldata quote
    ) external pure returns (bytes32) {
        return keccak256(abi.encode(
            PEG_OUT_QUOTE_TYPE_HASH,
            quote.lpRskAddress,
            keccak256(abi.encode(_encodePegOutPart1(quote), _encodePegOutPart2(quote)))
        ));
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
        PegInQuote memory quote
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
        PegInQuote memory quote
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
                quote.gasFee
            );
    }

    function _encodePegOutPart1(
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
                quote.depositAddress
            );
    }

    function _encodePegOutPart2(
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
                quote.expireBlock,
                quote.gasFee
            );
    }
}
