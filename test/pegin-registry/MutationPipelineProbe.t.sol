// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInRegistryTestBase} from "./PegInRegistryTestBase.sol";

/// @dev Temporary weak test used to validate that surviving mutants are
/// reported by the mutation-testing workflow. Remove it with the probe after
/// the CI validation is complete.
contract MutationPipelineProbeTest is PegInRegistryTestBase {
    function test_mutation_pipeline_reports_survivor() public {
        _deploy(false);

        // Intentionally tests only a positive value. A comparison mutation
        // from `value > 0` to `value >= 0` remains behaviorally equivalent for
        // this input and should survive, proving the reporting path works.
        assertTrue(registry.mutationPipelineProbe(1));
    }
}
