// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RequestPegInTestBase} from "./RequestPegInTestBase.sol";
import {PegInDerivation} from "../../src/libraries/PegInDerivation.sol";
import {BtcUtils} from "@rsksmart/btc-transaction-solidity-helper/contracts/BtcUtils.sol";

abstract contract ResolvePegInTestBase is RequestPegInTestBase {
    uint256 internal constant REGISTRANT_PAID_SLOT = 11;
    uint256 internal constant PEGIN_SETTLED_SLOT = 12;

    bytes internal constant WITNESS_MARKED_TX =
        hex"01000000000101000000000000000000000000000000000000000000000000000000000000000000ffffffff";

    function _minimalRawTx() internal pure returns (bytes memory) {
        bytes memory pkScript = hex"76a914000000000000000000000000000000000000000088ac";
        return
            abi.encodePacked(
                hex"01000000",
                hex"01",
                bytes32(uint256(1)),
                hex"00000000",
                hex"00",
                hex"ffffffff",
                hex"01",
                hex"008964000000000000",
                bytes1(uint8(pkScript.length)),
                pkScript,
                hex"00000000"
            );
    }

    function _btcTxHash(bytes memory rawTx) internal pure returns (bytes32) {
        return BtcUtils.hashBtcTx(rawTx);
    }

    function _derivationHash(address rskAddr) internal pure returns (bytes32) {
        return PegInDerivation.derivationArgumentsHash(rskAddr);
    }

    function _claimAndFund(
        address rskAddr,
        bytes memory rawTx,
        uint256 bridgeRelease
    ) internal returns (bytes32 pegInId) {
        bytes32 btcTxHash = _btcTxHash(rawTx);
        uint256 fee = _expectedFee(DEFAULT_AMOUNT);
        pegInId = _requestPegIn(claimer, rskAddr, DEFAULT_AMOUNT, btcTxHash, DEFAULT_AMOUNT - fee);
        bridgeMock.setPegin{value: bridgeRelease}(_derivationHash(rskAddr));
        return pegInId;
    }

    function _resolve(
        address caller,
        address rskAddr,
        bytes memory rawTx
    ) internal returns (int256) {
        vm.prank(caller);
        return pegInContract.resolvePegIn(rskAddr, rawTx, hex"00", 100);
    }

    function _balance(address account) internal view returns (uint256) {
        return pegInContract.getBalance(account);
    }

    function _isRegistrantPaid(address rskAddr) internal view returns (bool) {
        return
            uint256(
                vm.load(
                    address(pegInContract),
                    bytes32(uint256(keccak256(abi.encode(rskAddr, REGISTRANT_PAID_SLOT))))
                )
            ) == 1;
    }

    function _isSettled(bytes32 pegInId) internal view returns (bool) {
        return
            uint256(
                vm.load(
                    address(pegInContract),
                    bytes32(uint256(keccak256(abi.encode(pegInId, PEGIN_SETTLED_SLOT))))
                )
            ) == 1;
    }
}
