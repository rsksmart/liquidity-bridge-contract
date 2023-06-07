// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

/**
 * @title BtcUtils
 * @notice This library is based in this document https://developer.bitcoin.org/reference/transactions.html#raw-transaction-format
 */
library BtcUtils {
    bytes constant private ALPHABET = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    uint8 private constant MAX_COMPACT_SIZE_LENGTH = 252;
    uint8 private constant OUTPOINT_SIZE = 36;
    uint8 private constant OUTPUT_VALUE_SIZE = 8;
    uint8 private constant PUBKEY_HASH_SIZE = 20;
    uint8 private constant PUBKEY_HASH_START = 3;
    uint8 private constant CHECK_BYTES_FROM_HASH = 4;


    struct TxRawOutput {
        uint64 value;
        bytes pkScript;
        uint256 scriptSize;
        uint256 totalSize;
    }

    function parseCompactSizeInt(uint sizePosition, bytes memory array) private pure returns(uint64, uint16) {
        require(array.length > sizePosition, "Size position can't be bigger than array");
        uint8 maxSize = uint8(array[sizePosition]);
        if (maxSize <= MAX_COMPACT_SIZE_LENGTH) {
            return (maxSize, 0);
        }
        
        uint lastPosition = sizePosition + maxSize > array.length ? array.length - 1 : sizePosition + maxSize;
        uint64 result = uint64(calculateLittleEndianFragment(sizePosition + 1, lastPosition, array));
        return (result, maxSize);
    }

    function getOutputs(bytes calldata rawTx) public pure returns (TxRawOutput[] memory) {
        uint currentPosition = 4;
        
        (uint64 inputCount, uint16 inputCountSize) = parseCompactSizeInt(currentPosition, rawTx);
        currentPosition += inputCountSize + 1;

        uint64 scriptLarge;
        uint16 scriptLargeSize;
        for (uint64 i = 0; i < inputCount; i++) {
            currentPosition += OUTPOINT_SIZE;
            (scriptLarge, scriptLargeSize) = parseCompactSizeInt(currentPosition, rawTx);
            currentPosition += scriptLarge + scriptLargeSize + 4;
        }

        (uint64 outputCount, uint16 outputCountSize) = parseCompactSizeInt(++currentPosition, rawTx);
        currentPosition += outputCountSize;
        currentPosition++;

        TxRawOutput[] memory result = new TxRawOutput[](outputCount);
        for (uint i = 0; i < outputCount; i++) {
            result[i] = extractRawOutput(currentPosition, rawTx);
            currentPosition += result[i].totalSize;
        }
        return result;
    }

    function calculateLittleEndianFragment(uint fragmentStart, uint fragmentEnd, bytes memory array) private pure returns (uint) {
        require(
            fragmentStart < array.length && fragmentEnd < array.length, 
            "Range can't be bigger than array"
        );
        uint result = 0;
        for (uint i = fragmentStart; i <= fragmentEnd; i++) {
            result += uint8(array[i]) *  uint64(2 ** (8 * (i - (fragmentStart))));
        }
        return result;
    }

    function extractRawOutput(uint position, bytes memory rawTx) private pure returns (TxRawOutput memory) {
        TxRawOutput memory result;
        result.value = uint64(calculateLittleEndianFragment(position, position + OUTPUT_VALUE_SIZE, rawTx));
        position += OUTPUT_VALUE_SIZE;

        (uint64 scriptLength, uint16 scriptLengthSize) = parseCompactSizeInt(position, rawTx);
        position += scriptLengthSize;
        position++;

        bytes memory pkScript = new bytes(scriptLength);
        for (uint64 i = 0; i < scriptLength; i++) {
            pkScript[i] = rawTx[position + i];
        }
        result.pkScript = pkScript;
        result.scriptSize = scriptLength;
        result.totalSize = OUTPUT_VALUE_SIZE + scriptLength + scriptLengthSize + 1;
        return result;
    }

    function parsePayToAddressScript(bytes calldata outputScript, bool mainnet) public pure returns (bytes memory) {
        require(outputScript.length == 25, "Script has not the required length");
        require(
            outputScript[0] == 0x76 && // OP_DUP
            outputScript[1] == 0xa9 && // OP_HASH160
            outputScript[2] == 0x14 && // pubKeyHashSize, should be always 14 (20B)
            outputScript[23] == 0x88 && // OP_EQUALVERIFY
            outputScript[24] == 0xac, // OP_CHECKSIG
            "Script has not the required structure"
        );

        bytes memory destinationAddress = new bytes(PUBKEY_HASH_SIZE);
        for(uint8 i = PUBKEY_HASH_START; i < PUBKEY_HASH_SIZE + PUBKEY_HASH_START; i++) {
            destinationAddress[i - PUBKEY_HASH_START] = outputScript[i];
        }

        uint8 versionByte = mainnet? 0x00 : 0x6f;
        bytes memory result = addChecksumAndVersionByte(bytes1(versionByte), destinationAddress);

        
        return encodeAddressToBase58(result);
    }

    function parseOpReturnOuput(bytes calldata outputScript) public pure returns (bytes memory) {
        require(outputScript[0] == 0x6a, "Not OP_RETURN");
        require(
            outputScript.length > 2 && outputScript.length < 85,
            "Data out of bounds"
        );

        bytes memory message = new bytes(uint8(outputScript[1]));
        for (uint8 i = 0; i < message.length; i++) {
            // the addition of two is because the two first bytes correspond to the op_return opcode and the length of the message
            message[i] = outputScript[i + 2]; 
        }
        return message;
    }

    function addChecksumAndVersionByte(bytes1 versionByte, bytes memory source) private pure returns (bytes memory) {
        bytes memory dataWithVersion = new bytes(source.length + 1);
        dataWithVersion[0] = versionByte;

        uint8 i;
        for (i = 0; i < source.length; i++) {
            dataWithVersion[i + 1] = source[i];
        }

        bytes memory result = new bytes(dataWithVersion.length + CHECK_BYTES_FROM_HASH);
        bytes32 doubleSha256 = sha256(abi.encodePacked(sha256(dataWithVersion)));
        assembly {
            let len := mload(dataWithVersion)
            let dataPtr := add(dataWithVersion, 0x20)

            let resizedLen := mload(result)
            let resizedDataPtr := add(result, 0x20)

            let dataSize := sub(len, 0x20)
            let remaining := add(dataSize, 0x20)
            for { } gt(remaining, 0) { } {
                let chunkSize := lt(remaining, 0x20)
                mstore(resizedDataPtr, mload(dataPtr))
                dataPtr := add(dataPtr, 0x20)
                resizedDataPtr := add(resizedDataPtr, 0x20)
                remaining := sub(remaining, chunkSize)
            }
        }
    
        for (i = 0; i < CHECK_BYTES_FROM_HASH; i++) {
            result[result.length - (CHECK_BYTES_FROM_HASH - i)] = doubleSha256[i];
        }
        return result;
    }

    function encodeAddressToBase58(bytes memory data) private pure returns (bytes memory) {
        unchecked {
            uint256 size = data.length;
            uint256 zeroCount;
            while (zeroCount < size && data[zeroCount] == 0) {
                zeroCount++;
            }

            size = 34; // length of P2PKH address
            bytes memory slot = new bytes(size);
            uint32 carry;
            int256 m;
            int256 high = int256(size) - 1;
            for (uint256 i = 0; i < data.length; i++) {
                m = int256(size - 1);
                for (carry = uint8(data[i]); m > high || carry != 0; m--) {
                    carry = carry + 256 * uint8(slot[uint256(m)]);
                    slot[uint256(m)] = bytes1(uint8(carry % 58));
                    carry /= 58;
                }
                high = m;
            }

            uint256 n;
            for (n = zeroCount; n < size && slot[n] == 0; n++) {}
            size = slot.length - (n - zeroCount);
            bytes memory out = new bytes(size);
            for (uint256 i = 0; i < size; i++) {
                uint256 j = i + n - zeroCount;
                out[i] = ALPHABET[uint8(slot[j])];
            }
            return out;
        }
    }

    function hashBtcTx(bytes calldata btcTx) public pure returns (bytes32) {
        bytes memory doubleSha256 = abi.encodePacked(sha256(abi.encodePacked(sha256(btcTx))));
        bytes1 aux;
        for (uint i = 0; i < 16; i++) {
            aux = doubleSha256[i];
            doubleSha256[i] = doubleSha256[31 - i];
            doubleSha256[31 - i] = aux;
        }

        bytes32 result;
        assembly {
            result := mload(add(doubleSha256, 32))
        }
        return result;
    }
}