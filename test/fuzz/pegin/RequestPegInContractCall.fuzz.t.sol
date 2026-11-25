// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RequestPegInContractCallTestBase} from "../../pegin/RequestPegInContractCallTestBase.sol";

/// @title requestPegIn contract call: fuzz tests for the call gas and the amounts
contract RequestPegInContractCallFuzzTest is RequestPegInContractCallTestBase {
    /// @notice Whatever gas the LP sends, a claim that goes through gave the destination its full
    /// maxGasLimit, and the call succeeded
    /// @dev Unlike Rootstock, the test EVM keeps back 1/64 of the gas left at a CALL. CALL_GAS is
    /// small enough for the reserve to absorb that 1/64 as well, so the test checks the Rootstock
    /// property on the test EVM.
    function testFuzz_lpGas_neverStarvesTheCall(uint256 lpGas) public {
        lpGas = bound(lpGas, 300_000, 1_500_000);
        bytes memory depositTx = _callTx(address(recorder), CALL_GAS);
        bytes32 pegInId = _pegInIdForTx(rskUser, depositTx);
        uint256 value = _netToUser(CALL_GAS, GAS_PRICE);

        vm.prank(claimer);
        try
            pegInContract.requestPegIn{value: value, gas: lpGas}(
                rskUser,
                depositTx,
                bytes32(0),
                0,
                _emptyBranch()
            )
        {
            assertTrue(
                _claimSuccess(pegInId),
                "a claim that goes through made a successful call"
            );
            assertGe(
                recorder.gasAtEntry(),
                CALL_GAS,
                "the destination got its full maxGasLimit"
            );
        } catch {
            assertEq(recorder.calls(), 0);
        }
    }

    /// @notice The LP fronts the value sent, and the value sent plus all the fees is the deposit
    function testFuzz_amounts_addUp(
        uint32 maxGasLimit,
        uint64 gasPrice
    ) public {
        maxGasLimit = uint32(bound(maxGasLimit, 1, DEFAULT_MAX_CALL_GAS));
        gasPrice = uint64(
            bound(gasPrice, 0, _expected() / (uint256(maxGasLimit) + 2300))
        );
        vm.txGasPrice(gasPrice);
        // A plain address accepts RBTC with any gas, so the call always succeeds
        address wallet = makeAddr("wallet");
        bytes memory depositTx = _depositTxWithCall(
            rskUser,
            DEFAULT_AMOUNT,
            wallet,
            maxGasLimit,
            ""
        );
        bytes32 pegInId = _pegInIdForTx(rskUser, depositTx);

        uint256 callGasFee = _gasFee(maxGasLimit, gasPrice);
        _requestPegInTx(claimer, rskUser, depositTx, _expected() - callGasFee);

        (, uint256 frontedAmount, uint256 feeAtClaim, ) = _readClaim(pegInId);
        assertEq(wallet.balance + callGasFee, _expected());
        assertEq(
            frontedAmount + feeAtClaim + _readGasFeeAtClaim(pegInId),
            DEFAULT_AMOUNT
        );
    }
}
