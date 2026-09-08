// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ResolvePegInTestBase} from "./ResolvePegInTestBase.sol";
import {PegInDerivation} from "../../src/libraries/PegInDerivation.sol";

contract ResolvePegInRegtestTest is ResolvePegInTestBase {
    function test_regtest_end_to_end_settle_with_placeholders() public {
        address registrant = makeAddr("regtestRegistrant");
        registry.harness_seedRegistration(rskUser, registrant, 1);

        bytes memory rawTx = _depositTx(rskUser, DEFAULT_AMOUNT);
        bytes32 derivationHash = PegInDerivation.derivationArgumentsHash(
            rskUser
        );

        uint256 fee = _expectedFee(DEFAULT_AMOUNT);
        _requestPegInTx(claimer, rskUser, rawTx, DEFAULT_AMOUNT - fee);
        bridgeMock.setPegin{value: DEFAULT_AMOUNT + fee}(derivationHash);

        int256 result = _resolve(claimer, rskUser, rawTx);
        assertGt(result, 0);
        assertGt(_balance(claimer), 0);
        assertEq(_balance(registrant), 1e14);
        assertTrue(_isSettled(_pegInId(rskUser, _btcTxHash(rawTx))));
    }
}
