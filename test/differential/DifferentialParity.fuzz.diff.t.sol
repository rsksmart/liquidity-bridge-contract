// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {DifferentialBase} from "./base/DifferentialBase.sol";

/// @notice Unified fuzz differential suite.
contract DifferentialParityFuzzDiffTest is DifferentialBase {
    function testFuzz_quote_hashPegInQuoteForTarget_parity(
        uint96 _valueSeed,
        uint64 _callFeeSeed,
        uint32 _nonceSeed
    ) public {
        // TODO: build bounded valid quote from seeds and compare hash parity on configured fork.
    }

    function testFuzz_quote_hashPegInQuote_validationRevertCategory_parity(
        uint96 _valueSeed,
        uint64 _callFeeSeed,
        uint8 _invalidCaseSeed
    ) public {
        // TODO: derive invalid-case variants and compare revert category parity.
    }

    function testFuzz_quote_hashPegOutQuoteForTarget_parity(
        uint96 _valueSeed,
        uint64 _callFeeSeed,
        uint32 _nonceSeed
    ) public {
        // TODO: build bounded valid quote from seeds and compare hash parity on configured fork.
    }

    function testFuzz_quote_hashPegOutQuote_validationRevertCategory_parity(
        uint96 _valueSeed,
        address _lbcAddressSeed,
        uint8 _invalidCaseSeed
    ) public {
        // TODO: derive invalid-case variants and compare revert category parity.
    }
}
