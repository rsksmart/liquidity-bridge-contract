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
        bytes memory btcTx = _defaultTx();
        bytes32 pegInId = _pegInIdForTx(rskUser, btcTx);

        _requestPegInTx(claimer, rskUser, btcTx, net);

        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.PegInAlreadyProcessed.selector,
                pegInId
            )
        );
        pegInContract.requestPegIn{value: net}(
            rskUser,
            btcTx,
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
        bytes memory btcTx = _defaultTx();

        // Branch 1: nothing wired -> registry pointer nil is reported first.
        vm.prank(claimer);
        vm.expectRevert(PegInContract.PegInAddressRegistryNotSet.selector);
        unwired.requestPegIn{value: 1 ether}(
            rskUser,
            btcTx,
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
            btcTx,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );
    }

    // ---- Check 3: unregistered destination ----

    function test_revert_unregisteredRskAddr() public {
        address unregistered = makeAddr("unregistered");
        // Fixtures are built before vm.expectRevert: _depositTx reads the powpeg script from the
        // bridge, and expectRevert would otherwise arm against that read.
        bytes memory btcTx = _depositTx(unregistered, DEFAULT_AMOUNT);

        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.AddressNotRegistered.selector,
                unregistered
            )
        );
        pegInContract.requestPegIn{value: 1 ether}(
            unregistered,
            btcTx,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );
    }

    // ---- Check 4: no output pays the derived deposit address ----
    //
    // This is the check that closes the dust lockout. Before it existed, any confirmed txid
    // paired with any registered destination and a declared dust amount wrote the claim record
    // and locked every honest LP out of the real deposit under PegInAlreadyProcessed.

    function test_revert_depositOutputNotFound_unrelatedConfirmedTx() public {
        // A confirmed transaction that pays nothing this protocol derives — the attacker's
        // "any txid off the chain". Confirmations are satisfied; the derivation is not.
        bytes memory unrelated = _unrelatedTx();
        bytes32 txHash = this.hashTx(unrelated);

        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.DepositOutputNotFound.selector,
                rskUser,
                txHash
            )
        );
        pegInContract.requestPegIn{value: 1 wei}(
            rskUser,
            unrelated,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );
    }

    function test_revert_depositOutputNotFound_txPaysAnotherDestination()
        public
    {
        // A real Flyover deposit, but derived for someone else. Claiming it against rskUser is
        // the mismatched-transaction case: the output exists, it just is not rskUser's.
        address other = makeAddr("otherDestination");
        registry.harness_seedRegistration(other, makeAddr("registrant4"), 1);

        bytes memory othersDeposit = _depositTx(other, DEFAULT_AMOUNT);
        bytes32 txHash = this.hashTx(othersDeposit);

        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.DepositOutputNotFound.selector,
                rskUser,
                txHash
            )
        );
        pegInContract.requestPegIn{value: 1 wei}(
            rskUser,
            othersDeposit,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );
    }

    function test_dustClaim_cannotLockOutTheRealDeposit() public {
        // End to end on the original defect: the dust claim is rejected, and the real depositor
        // is served afterwards under the same pegInId the attacker tried to burn.
        bytes memory realDeposit = _defaultTx();
        bytes32 pegInId = _pegInIdForTx(rskUser, realDeposit);
        address attacker = makeAddr("attacker");
        vm.deal(attacker, 1 ether);

        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.DepositOutputNotFound.selector,
                rskUser,
                this.hashTx(_unrelatedTx())
            )
        );
        pegInContract.requestPegIn{value: 1 wei}(
            rskUser,
            _unrelatedTx(),
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );

        uint256 net = DEFAULT_AMOUNT - _expectedFee(DEFAULT_AMOUNT);
        _requestPegInTx(claimer, rskUser, realDeposit, net);

        (address claimerAddr, , , ) = _readClaim(pegInId);
        assertEq(claimerAddr, claimer, "honest LP still able to claim");
    }

    // ---- Check 5: insufficient confirmations ----

    function test_revert_insufficientConfirmations_tierBoundary() public {
        uint256 required = DEFAULT_TIER_CONFIRMATIONS;
        bridgeMock.setConfirmations(int256(required) - 1);
        bytes memory btcTx = _defaultTx();

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
            btcTx,
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
        bytes memory btcTx = _defaultTx();

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
            btcTx,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );
    }

    /// @notice The tier is looked up with the DERIVED amount, so a large deposit presented with
    /// only enough confirmations for a small one is rejected. Under the old signature the
    /// claimer simply declared the small amount and bought the low tier.
    function test_revert_largeDeposit_cannotBuyTheLowConfirmationTier() public {
        uint256 smallAmount = 1 ether;
        uint256 largeAmount = 50 ether;
        uint256 lowTierConfirmations = 2;
        uint256 highTierConfirmations = 40;
        _applyTwoTierConfiguration(
            smallAmount,
            lowTierConfirmations,
            highTierConfirmations
        );

        // Exactly the depth the small tier asks for, and no more.
        bridgeMock.setConfirmations(int256(lowTierConfirmations));
        vm.deal(claimer, 100 ether);
        bytes memory largeTx = _depositTx(rskUser, largeAmount);

        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.InsufficientConfirmations.selector,
                lowTierConfirmations,
                highTierConfirmations
            )
        );
        pegInContract.requestPegIn{
            value: largeAmount - _expectedFee(largeAmount)
        }(rskUser, largeTx, "", bytes32(0), 0, _emptyBranch());

        // The same depth serves a deposit that really is small.
        _requestPegIn(
            claimer,
            rskUser,
            smallAmount,
            smallAmount - _expectedFee(smallAmount)
        );
    }

    function test_confirmations_exactBoundaryPasses() public {
        bridgeMock.setConfirmations(int256(DEFAULT_TIER_CONFIRMATIONS));
        uint256 amount = DEFAULT_AMOUNT;
        uint256 net = amount - _expectedFee(amount);

        bytes32 pegInId = _requestPegIn(claimer, rskUser, amount, net);
        (address claimerAddr, , , ) = _readClaim(pegInId);
        assertEq(
            claimerAddr,
            claimer,
            "claim written at exact confirmation boundary"
        );
    }

    // ---- Check 6: incorrect fronting ----

    function test_revert_incorrectFronting_overstated() public {
        uint256 amount = DEFAULT_AMOUNT;
        uint256 expectedNet = amount - _expectedFee(amount);
        uint256 wrongValue = expectedNet + 1;
        bytes memory btcTx = _defaultTx();

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
            btcTx,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );
    }

    function test_revert_incorrectFronting_understated() public {
        uint256 amount = DEFAULT_AMOUNT;
        uint256 expectedNet = amount - _expectedFee(amount);
        uint256 wrongValue = expectedNet - 1;
        bytes memory btcTx = _defaultTx();

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
            btcTx,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );
    }

    /// @notice Fronting dust against a real, large deposit. The expected value in the error is
    /// the one derived from the deposit output, not anything the caller offered.
    function test_revert_incorrectFronting_dustAgainstRealDeposit() public {
        uint256 amount = DEFAULT_AMOUNT;
        uint256 expectedNet = amount - _expectedFee(amount);
        bytes memory btcTx = _defaultTx();

        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.IncorrectFronting.selector,
                expectedNet,
                1 wei
            )
        );
        pegInContract.requestPegIn{value: 1 wei}(
            rskUser,
            btcTx,
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
        bytes memory btcTx = _defaultTx();
        bytes32 pegInId = _pegInIdForTx(rskUser, btcTx);

        _requestPegInTx(claimer, rskUser, btcTx, net);

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
            btcTx,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );
    }

    function test_race_secondClaim_ordersBeforeConfirmationsCheck() public {
        uint256 amount = DEFAULT_AMOUNT;
        uint256 net = amount - _expectedFee(amount);
        bytes memory btcTx = _defaultTx();
        bytes32 pegInId = _pegInIdForTx(rskUser, btcTx);

        _requestPegInTx(claimer, rskUser, btcTx, net);

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
            btcTx,
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
        bytes memory btcTx = _defaultTx();
        bytes32 pegInId = _pegInIdForTx(rskUser, btcTx);
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
            btcTx,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );
    }

    /// @notice The already-processed check also wins over the derivation check: a second claim
    /// presenting a transaction that pays nobody still reports the claim race, not the
    /// derivation failure. Only the txid feeds the id, so the two are independent inputs.
    function test_ordering_alreadyProcessed_beforeDepositMatch() public {
        bytes memory unrelated = _unrelatedTx();
        bytes32 pegInId = _pegInIdForTx(rskUser, unrelated);
        _seedClaim(pegInContract, pegInId, claimer);

        vm.prank(claimer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.PegInAlreadyProcessed.selector,
                pegInId
            )
        );
        pegInContract.requestPegIn{value: 1 wei}(
            rskUser,
            unrelated,
            "",
            bytes32(0),
            0,
            _emptyBranch()
        );
    }
}
