// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ResolvePegInTestBase} from "./ResolvePegInTestBase.sol";
import {PegInDerivation} from "../../src/libraries/PegInDerivation.sol";

/// @title ResolvePegInRegtestTest
/// @notice T17 / R16 merge gate: end-to-end claimed settle with FLY-2521 placeholder bytes on regtest wiring
contract ResolvePegInRegtestTest is ResolvePegInTestBase {
    function test_regtest_end_to_end_settle_with_placeholders() public {
        address registrant = makeAddr("regtestRegistrant");
        registry.harness_seedRegistration(rskUser, registrant, 1);

        bytes memory rawTx = _minimalRawTx();
        bytes32 derivationHash = PegInDerivation.derivationArgumentsHash(rskUser);

        uint256 fee = _expectedFee(DEFAULT_AMOUNT);
        _requestPegIn(claimer, rskUser, DEFAULT_AMOUNT, _btcTxHash(rawTx), DEFAULT_AMOUNT - fee);
        bridgeMock.setPegin{value: DEFAULT_AMOUNT + fee}(derivationHash);

        int256 result = _resolve(claimer, rskUser, rawTx);
        assertGt(result, 0);
        assertGt(_balance(claimer), 0);
        assertEq(_balance(registrant), 1e14);
        assertTrue(_isSettled(_pegInId(rskUser, _btcTxHash(rawTx))));
    }
}
