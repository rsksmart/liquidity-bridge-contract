// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";
import {Quotes} from "../../../src/libraries/Quotes.sol";

/// @title Shared utilities for invariant handlers
abstract contract HandlerBase is Test {
    uint256 constant MIN_COLLATERAL = 0.6 ether;
    uint256 constant RESIGN_DELAY = 500;

    mapping(bytes32 => uint256) public handlerCalls;

    function getHandlerCalls(bytes32 name) external view returns (uint256) {
        return handlerCalls[name];
    }

    function _getProviderType(
        uint8 seed
    ) internal pure returns (Flyover.ProviderType) {
        uint8 bounded = seed % 3;
        if (bounded == 0) return Flyover.ProviderType.PegIn;
        if (bounded == 1) return Flyover.ProviderType.PegOut;
        return Flyover.ProviderType.Both;
    }

    function _getRequiredCollateral(
        Flyover.ProviderType providerType
    ) internal pure returns (uint256) {
        if (providerType == Flyover.ProviderType.Both) {
            return MIN_COLLATERAL * 2;
        }
        return MIN_COLLATERAL;
    }

    function _removeFromArray(bytes32[] storage arr, uint256 idx) internal {
        arr[idx] = arr[arr.length - 1];
        arr.pop();
    }

    function _generateName(uint256 seed) internal pure returns (string memory) {
        return string(abi.encodePacked("Provider-", vm.toString(seed)));
    }

    function _generateUrl(uint256 seed) internal pure returns (string memory) {
        return
            string(abi.encodePacked("https://lp-", vm.toString(seed), ".com"));
    }

    function _stagePegInQuote(
        Quotes.PegInQuote storage staged,
        address provider,
        uint256 penaltyFee,
        address lbcAddress
    ) internal {
        bytes memory testAddr = new bytes(20);
        bytes memory emptyBytes = new bytes(0);

        staged.penaltyFee = penaltyFee;
        staged.liquidityProviderRskAddress = provider;
        staged.lbcAddress = lbcAddress;
        staged.contractAddress = address(0);
        staged.rskRefundAddress = payable(address(0));
        staged.fedBtcAddress = bytes20(testAddr);
        staged.btcRefundAddress = testAddr;
        staged.liquidityProviderBtcAddress = testAddr;
        staged.data = emptyBytes;
    }

    function _stagePegOutSlashQuote(
        Quotes.PegOutQuote storage staged,
        address provider,
        uint256 penaltyFee,
        address lbcAddress
    ) internal {
        bytes memory testAddr = new bytes(20);

        staged.penaltyFee = penaltyFee;
        staged.lpRskAddress = provider;
        staged.lbcAddress = lbcAddress;
        staged.depositAddress = testAddr;
        staged.btcRefundAddress = testAddr;
        staged.lpBtcAddress = testAddr;
    }

    function _stagePegOutDepositQuote(
        Quotes.PegOutQuote storage staged,
        address lpAddr,
        uint256 value,
        address lbcAddress,
        address refundAddress,
        uint256 nonce
    ) internal {
        bytes memory btcAddr = abi.encodePacked(
            hex"6f",
            hex"89abcdefabbaabbaabbaabbaabbaabbaabbaabba"
        );
        staged.chainId = block.chainid;
        staged.callFee = 0.001 ether;
        staged.penaltyFee = 0.0001 ether;
        staged.value = value;
        staged.gasFee = 100;
        staged.lbcAddress = lbcAddress;
        staged.lpRskAddress = lpAddr;
        staged.rskRefundAddress = refundAddress;
        staged.nonce = int64(int256(nonce));
        staged.agreementTimestamp = uint32(block.timestamp);
        staged.depositDateLimit = uint32(block.timestamp + 7200);
        staged.transferTime = 3600;
        staged.depositConfirmations = 10;
        staged.transferConfirmations = 2;
        staged.expireBlock = uint32(block.number + 4000);
        staged.expireDate = uint32(block.timestamp + 20000);
        staged.depositAddress = btcAddr;
        staged.btcRefundAddress = btcAddr;
        staged.lpBtcAddress = btcAddr;
    }
}
