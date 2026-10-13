// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {QuotesV2} from "../../src/legacy/QuotesV2.sol";
import {DifferentialBase} from "./base/DifferentialBase.sol";
import {IDifferentialAdapter} from "./adapters/IDifferentialAdapter.sol";

/// @notice Unified regular differential suite (non-fuzz).
contract DifferentialParityDiffTest is DifferentialBase {
    // ---------------------------------------------------------------------
    // Core quote parity (implemented)
    // ---------------------------------------------------------------------

    function test_quote_hashPegOutQuoteForTarget_parity() public {
        NetworkHarness storage harness = _getHarness();
        vm.selectFork(harness.forkId);

        IDifferentialAdapter refAdapter = harness.referenceAdapter;
        IDifferentialAdapter candidate = harness.candidateAdapter;

        QuotesV2.PegOutQuote memory quote = _buildValidPegOutQuote();

        (bool refOk, bytes memory refData) = _callStatic(
            address(refAdapter),
            abi.encodeCall(
                IDifferentialAdapter.hashPegOutQuoteForTarget,
                (quote)
            )
        );
        (bool candOk, bytes memory candData) = _callStatic(
            address(candidate),
            abi.encodeCall(
                IDifferentialAdapter.hashPegOutQuoteForTarget,
                (quote)
            )
        );

        require(refOk == candOk, "PegOut hash pass/fail mismatch");
        require(refOk, "Expected both hash calls to succeed");

        (bool refOkSecond, bytes memory refDataSecond) = _callStatic(
            address(refAdapter),
            abi.encodeCall(
                IDifferentialAdapter.hashPegOutQuoteForTarget,
                (quote)
            )
        );
        (bool candOkSecond, bytes memory candDataSecond) = _callStatic(
            address(candidate),
            abi.encodeCall(
                IDifferentialAdapter.hashPegOutQuoteForTarget,
                (quote)
            )
        );
        require(
            refOkSecond && candOkSecond,
            "Expected deterministic re-hash success"
        );
        require(
            keccak256(refData) == keccak256(refDataSecond),
            "Reference PegOut hash not deterministic"
        );
        require(
            keccak256(candData) == keccak256(candDataSecond),
            "Candidate PegOut hash not deterministic"
        );

        QuotesV2.PegOutQuote memory changedQuote = quote;
        changedQuote.nonce = quote.nonce + 1;
        (bool refChangedOk, bytes memory refChangedData) = _callStatic(
            address(refAdapter),
            abi.encodeCall(
                IDifferentialAdapter.hashPegOutQuoteForTarget,
                (changedQuote)
            )
        );
        (bool candChangedOk, bytes memory candChangedData) = _callStatic(
            address(candidate),
            abi.encodeCall(
                IDifferentialAdapter.hashPegOutQuoteForTarget,
                (changedQuote)
            )
        );
        require(
            refChangedOk == candChangedOk,
            "PegOut changed-quote pass/fail mismatch"
        );
        require(refChangedOk, "Expected changed quote hash to succeed");
        require(
            keccak256(refData) != keccak256(refChangedData),
            "Reference PegOut hash should change when nonce changes"
        );
        require(
            keccak256(candData) != keccak256(candChangedData),
            "Candidate PegOut hash should change when nonce changes"
        );
    }

    function test_quote_hashPegOutQuoteRaw_revertsForIncorrectContract_parity()
        public
    {
        NetworkHarness storage harness = _getHarness();
        vm.selectFork(harness.forkId);

        IDifferentialAdapter refAdapter = harness.referenceAdapter;
        IDifferentialAdapter candidate = harness.candidateAdapter;

        QuotesV2.PegOutQuote memory quote = _buildValidPegOutQuote();
        quote.lbcAddress = address(0x123456);

        (bool refOk, bytes memory refData) = _callStatic(
            address(refAdapter),
            abi.encodeCall(IDifferentialAdapter.hashPegOutQuoteRaw, (quote))
        );
        (bool candOk, bytes memory candData) = _callStatic(
            address(candidate),
            abi.encodeCall(IDifferentialAdapter.hashPegOutQuoteRaw, (quote))
        );

        _assertSameOutcome(
            refOk,
            refData,
            candOk,
            candData,
            "PegOut lbcAddress validation mismatch"
        );
        require(!refOk, "Expected wrong PegOut lbcAddress to revert");
    }

    // ---------------------------------------------------------------------
    // Configuration parity (skeleton)
    // ---------------------------------------------------------------------

    function test_config_bridgeAddress_parity() public {
        // TODO: compare reference vs candidate bridge address normalization.
    }

    function test_config_minPegIn_parity() public {
        // TODO: compare reference vs candidate minimum peg-in values.
    }

    function test_config_minCollateral_parity() public {
        // TODO: compare reference vs candidate minimum collateral values.
    }

    function test_config_rewardPercentage_parity() public {
        // TODO: compare reference vs candidate reward percentage values.
    }

    function test_config_resignDelayBlocks_parity() public {
        // TODO: compare reference vs candidate resign-delay values.
    }

    function test_config_dustThreshold_parity() public {
        // TODO: compare reference vs candidate dust threshold values.
    }

    // ---------------------------------------------------------------------
    // Discovery parity (skeleton)
    // ---------------------------------------------------------------------

    function test_discovery_registerProvider_successPath_parity() public {
        // TODO: compare successful provider registration behavior and resulting state.
    }

    function test_discovery_registerProvider_revertCategory_parity() public {
        // TODO: compare failure category for invalid registration inputs.
    }

    function test_discovery_providerOperationalStatus_parity() public {
        // TODO: compare provider operational status outcome after registration.
    }

    function test_discovery_providerListingEligibility_parity() public {
        // TODO: compare listing eligibility behavior (enabled/disabled + collateral).
    }

    // ---------------------------------------------------------------------
    // Liquidity parity (skeleton)
    // ---------------------------------------------------------------------

    function test_liquidity_deposit_successPath_parity() public {
        // TODO: compare provider collateral/liquidity update after deposit.
    }

    function test_liquidity_deposit_revertCategory_parity() public {
        // TODO: compare failure category for invalid deposit attempts.
    }

    function test_liquidity_withdraw_successPath_parity() public {
        // TODO: compare collateral/liquidity update after withdraw.
    }

    function test_liquidity_withdraw_revertCategory_parity() public {
        // TODO: compare failure category for invalid withdraw attempts.
    }

    function test_liquidity_pegoutCapacityTracking_parity() public {
        // TODO: compare effective peg-out capacity changes across lifecycle.
    }

    // ---------------------------------------------------------------------
    // Refund parity (skeleton)
    // ---------------------------------------------------------------------

    function test_refunds_refundQuoteHash_parity() public {
        // TODO: compare hash parity and canonical quote encoding assumptions.
    }

    function test_refunds_refundEligibility_successPath_parity() public {
        // TODO: compare eligibility result for valid refundable cases.
    }

    function test_refunds_refundEligibility_revertCategory_parity() public {
        // TODO: compare failure category for non-refundable/invalid cases.
    }

    function test_refunds_refundExecution_stateDelta_parity() public {
        // TODO: compare state deltas and invariant preservation after refund.
    }

    // ---------------------------------------------------------------------
    // Slashing parity (skeleton)
    // ---------------------------------------------------------------------

    function test_slashing_slashQuoteHash_parity() public {
        // TODO: compare quote/hash determinism used by slashing paths.
    }

    function test_slashing_slash_preconditions_parity() public {
        // TODO: compare precondition checks (timing, signatures, status).
    }

    function test_slashing_slashExecution_stateDelta_parity() public {
        // TODO: compare state changes to provider balances/collateral on slash.
    }

    function test_slashing_slash_revertCategory_parity() public {
        // TODO: compare failure category for invalid slashing attempts.
    }

    function _buildValidPegOutQuote()
        internal
        view
        returns (QuotesV2.PegOutQuote memory quote)
    {
        bytes memory btcAddr = _btcAddress21();

        quote = QuotesV2.PegOutQuote({
            lbcAddress: address(0),
            lpRskAddress: address(0x4004),
            btcRefundAddress: btcAddr,
            rskRefundAddress: address(0x5005),
            lpBtcAddress: btcAddr,
            callFee: 100_000_000_000_000,
            penaltyFee: 10_000_000_000_000,
            nonce: 2,
            deposityAddress: btcAddr,
            value: 500_000_000_000_000_000,
            agreementTimestamp: uint32(block.timestamp),
            depositDateLimit: uint32(block.timestamp + 3_600),
            depositConfirmations: 40,
            transferConfirmations: 2,
            transferTime: 3_600,
            expireDate: uint32(block.timestamp + 7_200),
            expireBlock: uint32(block.number + 100),
            productFeeAmount: 0,
            gasFee: 10_000
        });
    }

    function _btcAddress21() internal pure returns (bytes memory) {
        return hex"6f00112233445566778899aabbccddeeff00112233";
    }
}
