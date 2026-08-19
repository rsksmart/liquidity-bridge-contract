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

    function _btcTxHash(bytes memory rawTx) internal pure returns (bytes32) {
        return BtcUtils.hashBtcTx(rawTx);
    }

    function _derivationHash(address rskAddr) internal pure returns (bytes32) {
        return PegInDerivation.derivationArgumentsHash(rskAddr);
    }

    function _claimAndFund(
        address rskAddr,
        bytes memory depositTx,
        uint256 bridgeRelease
    ) internal returns (bytes32 pegInId) {
        pegInId = _requestPegInTx(
            claimer,
            rskAddr,
            depositTx,
            DEFAULT_AMOUNT - _expectedFee(DEFAULT_AMOUNT)
        );
        bridgeMock.setPegin{value: bridgeRelease}(_derivationHash(rskAddr));
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
                    bytes32(
                        uint256(
                            keccak256(abi.encode(rskAddr, REGISTRANT_PAID_SLOT))
                        )
                    )
                )
            ) == 1;
    }

    function _isSettled(bytes32 pegInId) internal view returns (bool) {
        return
            uint256(
                vm.load(
                    address(pegInContract),
                    bytes32(
                        uint256(
                            keccak256(abi.encode(pegInId, PEGIN_SETTLED_SLOT))
                        )
                    )
                )
            ) == 1;
    }
}
