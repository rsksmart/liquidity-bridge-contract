// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {RequestPegInTestBase} from "./RequestPegInTestBase.sol";
import {PegInContract} from "../../src/PegInContract.sol";
import {IPegInCommitFirst} from "../../src/interfaces/IPegInCommitFirst.sol";

/// @title requestPegIn ordered-check revert and race/ordering tests
/// @notice One test per check with the specific custom error and its arguments, plus proofs that
/// the already-processed check (check 1) runs before every later check.
contract RequestPegInRevertsTest is RequestPegInTestBase {
    // _pegInAddressRegistry under lockfile-pinned OZ 5.5.0 (forge inspect after npm ci).
    uint256 private constant REGISTRY_SLOT = 8;

    // ---- Check 1: already processed ----

    function test_revert_alreadyProcessed_secondClaimSameId() public {
        uint256 amount = DEFAULT_AMOUNT;
        uint256 net = amount - _expectedFee(amount);
        bytes32 pegInId = _pegInId(rskUser, DEFAULT_BTC_TX_HASH);

        _requestPegIn(claimer, rskUser, amount, DEFAULT_BTC_TX_HASH, net);

        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.PegInAlreadyProcessed.selector,
                pegInId
            )
        );
        pegInContract.requestPegIn{value: net}(
            rskUser,
            amount,
            DEFAULT_BTC_TX_HASH,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );
    }

    // ---- Check 2: dependencies not set ----

    function test_revert_depsNotSet_registryThenConfigurations() public {
        // Both branches of _requirePegInDepsSet on one unwired deployment: registry is checked
        // before configurations, so the errors surface in that order as each pointer is wired.
        PegInContract unwired = _deployUnwiredPegInContract();

        // Branch 1: nothing wired -> registry pointer nil is reported first.
        vm.prank(claimer);
        vm.expectRevert(PegInContract.PegInAddressRegistryNotSet.selector);
        unwired.requestPegIn{value: 1 ether}(
            rskUser,
            DEFAULT_AMOUNT,
            DEFAULT_BTC_TX_HASH,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );

        // Branch 2: wire only the registry pointer, leaving configurations unset.
        vm.store(
            address(unwired),
            bytes32(REGISTRY_SLOT),
            bytes32(uint256(uint160(address(registry))))
        );

        vm.prank(claimer);
        vm.expectRevert(PegInContract.FlyoverConfigurationsNotSet.selector);
        unwired.requestPegIn{value: 1 ether}(
            rskUser,
            DEFAULT_AMOUNT,
            DEFAULT_BTC_TX_HASH,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );
    }

    // ---- Check 3: unregistered destination ----

    function test_revert_unregisteredRskAddr() public {
        address unregistered = makeAddr("unregistered");

        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.AddressNotRegistered.selector,
                unregistered
            )
        );
        pegInContract.requestPegIn{value: 1 ether}(
            unregistered,
            DEFAULT_AMOUNT,
            DEFAULT_BTC_TX_HASH,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );
    }

    // ---- Check 4: insufficient confirmations ----

    function test_revert_insufficientConfirmations_tierBoundary() public {
        uint256 required = DEFAULT_TIER_CONFIRMATIONS;
        bridgeMock.setConfirmations(int256(required) - 1);

        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.InsufficientConfirmations.selector,
                required - 1,
                required
            )
        );
        pegInContract.requestPegIn{value: 1 ether}(
            rskUser,
            DEFAULT_AMOUNT,
            DEFAULT_BTC_TX_HASH,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );
    }

    function test_revert_insufficientConfirmations_negativeBridgeReportsZeroHave()
        public
    {
        uint256 required = DEFAULT_TIER_CONFIRMATIONS;
        bridgeMock.setConfirmations(-1);

        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.InsufficientConfirmations.selector,
                0,
                required
            )
        );
        pegInContract.requestPegIn{value: 1 ether}(
            rskUser,
            DEFAULT_AMOUNT,
            DEFAULT_BTC_TX_HASH,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );
    }

    function test_confirmations_exactBoundaryPasses() public {
        bridgeMock.setConfirmations(int256(DEFAULT_TIER_CONFIRMATIONS));
        uint256 amount = DEFAULT_AMOUNT;
        uint256 net = amount - _expectedFee(amount);

        bytes32 pegInId = _requestPegIn(
            claimer,
            rskUser,
            amount,
            DEFAULT_BTC_TX_HASH,
            net
        );
        (address claimerAddr, , , ) = _readClaim(pegInId);
        assertEq(
            claimerAddr,
            claimer,
            "claim written at exact confirmation boundary"
        );
    }

    // ---- Check 5: incorrect fronting ----

    function test_revert_incorrectFronting_wrongValue() public {
        uint256 amount = DEFAULT_AMOUNT;
        uint256 expectedNet = amount - _expectedFee(amount);
        uint256 wrongValue = expectedNet + 1;

        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.IncorrectFronting.selector,
                expectedNet,
                wrongValue
            )
        );
        pegInContract.requestPegIn{value: wrongValue}(
            rskUser,
            amount,
            DEFAULT_BTC_TX_HASH,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );
    }

    // ---- Race / ordering (A1 / D11): check 1 runs before every later check ----

    function test_race_secondClaim_ordersBeforeFrontingCheck() public {
        uint256 amount = DEFAULT_AMOUNT;
        uint256 net = amount - _expectedFee(amount);
        bytes32 pegInId = _pegInId(rskUser, DEFAULT_BTC_TX_HASH);

        _requestPegIn(claimer, rskUser, amount, DEFAULT_BTC_TX_HASH, net);

        // Second claim with a deliberately wrong value still reverts already-processed,
        // never IncorrectFronting.
        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.PegInAlreadyProcessed.selector,
                pegInId
            )
        );
        pegInContract.requestPegIn{value: net + 123}(
            rskUser,
            amount,
            DEFAULT_BTC_TX_HASH,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );
    }

    function test_race_secondClaim_ordersBeforeConfirmationsCheck() public {
        uint256 amount = DEFAULT_AMOUNT;
        uint256 net = amount - _expectedFee(amount);
        bytes32 pegInId = _pegInId(rskUser, DEFAULT_BTC_TX_HASH);

        _requestPegIn(claimer, rskUser, amount, DEFAULT_BTC_TX_HASH, net);

        // Drop confirmations below tier; already-processed still wins.
        bridgeMock.setConfirmations(0);
        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.PegInAlreadyProcessed.selector,
                pegInId
            )
        );
        pegInContract.requestPegIn{value: net}(
            rskUser,
            amount,
            DEFAULT_BTC_TX_HASH,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );
    }

    function test_ordering_alreadyProcessed_beforeDepsAndRegistration() public {
        // Unwired contract (deps unset) with a pre-seeded claim and an unregistered rskAddr:
        // check 1 must still win over the deps-set and registration checks.
        PegInContract unwired = _deployUnwiredPegInContract();
        bytes32 pegInId = _pegInId(rskUser, DEFAULT_BTC_TX_HASH);
        _seedClaim(unwired, pegInId, claimer);

        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.PegInAlreadyProcessed.selector,
                pegInId
            )
        );
        unwired.requestPegIn{value: 1 ether}(
            rskUser,
            DEFAULT_AMOUNT,
            DEFAULT_BTC_TX_HASH,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );
    }
}
