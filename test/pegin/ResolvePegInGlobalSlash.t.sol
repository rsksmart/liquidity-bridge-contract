// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ResolvePegInTestBase} from "./ResolvePegInTestBase.sol";
import {Vm} from "forge-std/Vm.sol";
import {IPegInCommitFirst} from "../../src/interfaces/IPegInCommitFirst.sol";
import {ICollateralManagement} from "../../src/interfaces/ICollateralManagement.sol";
import {IPauseRegistry} from "../../src/interfaces/IPauseRegistry.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";

contract ResolvePegInGlobalSlashTest is ResolvePegInTestBase {
    uint256 internal constant T = 1_700_000_000;
    uint256 internal constant PENALTY_FEE = 0.1 ether;
    uint256 internal constant CLAIM_WINDOW = 3 hours;
    uint256 internal constant BRIDGE_RELEASE = DEFAULT_AMOUNT;
    uint256 internal constant RESOLVE_HEIGHT = 100;
    uint256 internal constant MAX_SLASHABLE_TX_SIZE = 3_000;
    /// @dev RSK's 10M block gas limit minus room for the real bridge call, which the mock does
    /// not charge
    uint256 internal constant SETTLE_GAS_BUDGET = 8_000_000;

    address internal secondLp;
    address internal thirdParty;

    function setUp() public override {
        super.setUp();

        vm.startPrank(owner);
        collateralManagement.setFlyoverDiscovery(address(discovery));
        collateralManagement.setGlobalSlashGraceBlocks(0);
        vm.stopPrank();

        configurations.setPenaltyFee(PENALTY_FEE);
        configurations.setClaimWindow(CLAIM_WINDOW);

        secondLp = makeAddr("secondLp");
        vm.deal(secondLp, 10 ether);
        vm.prank(secondLp, secondLp);
        discovery.register{value: 2 * MIN_COLLATERAL}(
            "Second LP",
            "second.com",
            true,
            Flyover.ProviderType.PegIn
        );
        vm.prank(owner);
        discovery.approveRegistration(secondLp);

        thirdParty = makeAddr("thirdParty");

        vm.roll(1_000);
        vm.warp(T);
    }

    // ---- helpers ----

    function _headerWithTimestamp(
        uint32 ts
    ) internal pure returns (bytes memory header) {
        header = new bytes(80);
        header[68] = bytes1(uint8(ts));
        header[69] = bytes1(uint8(ts >> 8));
        header[70] = bytes1(uint8(ts >> 16));
        header[71] = bytes1(uint8(ts >> 24));
    }

    function _setTierHeader(uint32 ts) internal {
        uint256 tier = configurations.getRequiredPegInBtcConfirmations(
            DEFAULT_AMOUNT
        );
        bridgeMock.setHeader(
            RESOLVE_HEIGHT + tier - 1,
            _headerWithTimestamp(ts)
        );
    }

    function _passClaimWindow() internal {
        vm.warp(T + CLAIM_WINDOW + 1);
    }

    function _fund(address rskAddr) internal {
        bridgeMock.setPegin{value: BRIDGE_RELEASE}(_derivationHash(rskAddr));
    }

    function _settle(
        address rskAddr,
        bytes memory depositTx
    ) internal returns (Vm.Log[] memory logs) {
        _fund(rskAddr);
        logs = _resolveAndAssertUserPaid(rskAddr, depositTx);
    }

    function _resolveAndAssertUserPaid(
        address rskAddr,
        bytes memory depositTx
    ) internal returns (Vm.Log[] memory logs) {
        uint256 userBefore = rskAddr.balance;
        vm.recordLogs();
        _resolve(thirdParty, rskAddr, depositTx);
        logs = vm.getRecordedLogs();
        assertEq(
            rskAddr.balance - userBefore,
            BRIDGE_RELEASE,
            "user must receive the whole release"
        );
    }

    /// @dev A deposit to rskAddr padded to exactly `size` bytes with empty-script outputs. Many
    /// short outputs cost the most gas to parse per byte, so this is the worst case for a size.
    function _depositTxOfSize(
        address rskAddr,
        uint256 size
    ) internal view returns (bytes memory depositTx) {
        bytes memory pkScript = _depositPkScript(rskAddr);
        uint64 sats = _toSats(DEFAULT_AMOUNT);
        bytes memory value = new bytes(8);
        for (uint256 i; i < 8; ++i) {
            value[i] = bytes1(uint8(sats >> (8 * i)));
        }
        bytes memory outputs = abi.encodePacked(
            value,
            bytes1(uint8(pkScript.length)),
            pkScript
        );
        // version, input count, input, 3-byte output count, locktime
        uint256 padding = size - (4 + 1 + 41 + 3 + 4) - outputs.length;
        uint256 paddingOutputs = padding / 9;
        for (uint256 i = 1; i < paddingOutputs; ++i) {
            outputs = bytes.concat(outputs, new bytes(9));
        }
        uint256 lastScriptLength = padding - 9 * paddingOutputs;
        outputs = bytes.concat(
            outputs,
            new bytes(8),
            bytes1(uint8(lastScriptLength)),
            new bytes(lastScriptLength)
        );
        uint256 outputCount = 1 + paddingOutputs;
        depositTx = abi.encodePacked(
            hex"01000000", // version
            hex"01", // input count
            bytes32(DEFAULT_TX_NONCE), // prevout txid
            hex"00000000", // prevout index
            hex"00", // empty scriptSig
            hex"ffffffff", // sequence
            hex"fd",
            bytes1(uint8(outputCount)),
            bytes1(uint8(outputCount >> 8)),
            outputs,
            hex"00000000" // locktime
        );
        assertEq(depositTx.length, size);
    }

    function _count(
        Vm.Log[] memory logs,
        bytes32 topic
    ) internal view returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].topics.length > 0 &&
                logs[i].topics[0] == topic &&
                (logs[i].emitter == address(collateralManagement) ||
                    logs[i].emitter == address(pegInContract))
            ) {
                ++n;
            }
        }
    }

    function _totalPegInCollateral() internal view returns (uint256) {
        return
            collateralManagement.getPegInCollateral(claimer) +
            collateralManagement.getPegInCollateral(secondLp);
    }

    function _assertSkipped(Vm.Log[] memory logs) internal view {
        assertEq(_totalPegInCollateral(), 3 * MIN_COLLATERAL);
        assertEq(
            _count(logs, ICollateralManagement.PegInGlobalSlashShare.selector),
            0
        );
        assertEq(
            _count(logs, IPegInCommitFirst.GlobalSlashSkipped.selector),
            0
        );
    }

    function _assertSlashed(
        Vm.Log[] memory logs,
        uint256 collateralBefore
    ) internal view {
        assertEq(_totalPegInCollateral(), collateralBefore - PENALTY_FEE);
        assertEq(
            _count(logs, ICollateralManagement.PegInGlobalSlashShare.selector),
            2
        );
        assertEq(
            _count(logs, IPegInCommitFirst.GlobalSlashSkipped.selector),
            0
        );
    }

    // ---- tests ----

    function test_unclaimed_serviceable_deposit_slashes_peg_in_lps() public {
        _setTierHeader(uint32(T));
        _passClaimWindow();
        uint256 claimerCollateral = collateralManagement.getPegInCollateral(
            claimer
        );
        uint256 secondLpCollateral = collateralManagement.getPegInCollateral(
            secondLp
        );
        uint256 totalCollateral = claimerCollateral + secondLpCollateral;
        uint256 claimerShare = (PENALTY_FEE * claimerCollateral) /
            totalCollateral;
        // The contract gives the last LP the rounding remainder
        uint256 secondLpShare = PENALTY_FEE - claimerShare;
        _fund(rskUser);

        vm.expectEmit(true, true, false, true, address(collateralManagement));
        emit ICollateralManagement.PegInGlobalSlashShare(claimer, claimerShare);
        vm.expectEmit(true, true, false, true, address(collateralManagement));
        emit ICollateralManagement.PegInGlobalSlashShare(
            secondLp,
            secondLpShare
        );
        Vm.Log[] memory logs = _resolveAndAssertUserPaid(rskUser, _defaultTx());

        assertEq(
            collateralManagement.getPegInCollateral(claimer),
            claimerCollateral - claimerShare
        );
        assertEq(
            collateralManagement.getPegInCollateral(secondLp),
            secondLpCollateral - secondLpShare
        );
        assertEq(
            _count(logs, IPegInCommitFirst.GlobalSlashSkipped.selector),
            0
        );
    }

    function test_unclaimed_deposit_below_min_amount_skips_slash() public {
        _setTierHeader(uint32(T));
        _passClaimWindow();
        bytes memory depositTx = _depositTx(
            rskUser,
            TEST_MIN_PEGIN - Flyover.SAT_TO_WEI_CONVERSION
        );

        _assertSkipped(_settle(rskUser, depositTx));
    }

    function test_unclaimed_deposit_output_below_bridge_minimum_skips_slash()
        public
    {
        _setTierHeader(uint32(T));
        _passClaimWindow();
        bytes[] memory pkScripts = new bytes[](2);
        pkScripts[0] = _depositPkScript(rskUser);
        pkScripts[1] = _depositPkScript(rskUser);
        uint64[] memory valuesSats = new uint64[](2);
        valuesSats[0] = _toSats(DEFAULT_AMOUNT);
        valuesSats[1] = uint64(TEST_BRIDGE_MIN_DEPOSIT_SATS - 1);

        _assertSkipped(_settle(rskUser, _buildTx(pkScripts, valuesSats, 1)));
    }

    function test_unclaimed_deposit_below_deduction_skips_slash() public {
        configurations.setFee(DEFAULT_AMOUNT + 1, 0);
        _setTierHeader(uint32(T));
        _passClaimWindow();

        _assertSkipped(_settle(rskUser, _defaultTx()));
    }

    function test_unclaimed_deposit_without_derived_output_skips_slash()
        public
    {
        _setTierHeader(uint32(T));
        _passClaimWindow();

        _assertSkipped(_settle(rskUser, _unrelatedTx()));
    }

    // ---- OP_RETURN: a deposit no LP may claim is not slashable ----

    function test_unclaimed_deposit_with_bad_push_op_return_skips_slash()
        public
    {
        _setTierHeader(uint32(T));
        _passClaimWindow();

        _assertSkipped(
            _settle(
                rskUser,
                _depositTxWithScript(rskUser, DEFAULT_AMOUNT, hex"6a")
            )
        );
    }

    function test_unclaimed_deposit_with_wrong_magic_op_return_skips_slash()
        public
    {
        bytes memory payload = _callPayload(
            makeAddr("destination"),
            100_000,
            ""
        );
        payload[0] = 0xF1;
        _setTierHeader(uint32(T));
        _passClaimWindow();

        _assertSkipped(
            _settle(
                rskUser,
                _depositTxWithScript(
                    rskUser,
                    DEFAULT_AMOUNT,
                    _opReturnScript(payload)
                )
            )
        );
    }

    function test_unclaimed_deposit_with_zero_destination_op_return_skips_slash()
        public
    {
        _setTierHeader(uint32(T));
        _passClaimWindow();

        _assertSkipped(
            _settle(
                rskUser,
                _depositTxWithCall(
                    rskUser,
                    DEFAULT_AMOUNT,
                    address(0),
                    100_000,
                    ""
                )
            )
        );
    }

    function test_unclaimed_deposit_with_zero_max_gas_limit_skips_slash()
        public
    {
        _setTierHeader(uint32(T));
        _passClaimWindow();

        _assertSkipped(
            _settle(
                rskUser,
                _depositTxWithCall(
                    rskUser,
                    DEFAULT_AMOUNT,
                    makeAddr("destination"),
                    0,
                    ""
                )
            )
        );
    }

    function test_unclaimed_deposit_with_max_gas_limit_above_max_call_gas_skips_slash()
        public
    {
        _setTierHeader(uint32(T));
        _passClaimWindow();

        _assertSkipped(
            _settle(
                rskUser,
                _depositTxWithCall(
                    rskUser,
                    DEFAULT_AMOUNT,
                    makeAddr("destination"),
                    uint32(DEFAULT_MAX_CALL_GAS + 1),
                    ""
                )
            )
        );
    }

    /// @notice A valid OP_RETURN does not change the slash rule, and the unclaimed settlement pays
    /// rskAddr without calling the destination
    function test_unclaimed_deposit_with_valid_op_return_slashes_and_makes_no_call()
        public
    {
        address callTarget = makeAddr("destination");
        bytes memory callData = hex"deadbeef";
        _setTierHeader(uint32(T));
        _passClaimWindow();
        uint256 collateralBefore = _totalPegInCollateral();

        vm.expectCall(callTarget, callData, 0);
        Vm.Log[] memory logs = _settle(
            rskUser,
            _depositTxWithCall(
                rskUser,
                DEFAULT_AMOUNT,
                callTarget,
                100_000,
                callData
            )
        );

        _assertSlashed(logs, collateralBefore);
    }

    function test_unclaimed_deposit_to_unregistered_address_skips_slash()
        public
    {
        address unregistered = makeAddr("unregistered");
        _setTierHeader(uint32(T));
        _passClaimWindow();

        _assertSkipped(
            _settle(unregistered, _depositTx(unregistered, DEFAULT_AMOUNT))
        );
    }

    function test_unclaimed_deposit_at_size_limit_slashes_within_gas_budget()
        public
    {
        _setTierHeader(uint32(T));
        _passClaimWindow();
        bytes memory depositTx = _depositTxOfSize(
            rskUser,
            MAX_SLASHABLE_TX_SIZE
        );
        uint256 collateralBefore = _totalPegInCollateral();
        uint256 userBefore = rskUser.balance;
        _fund(rskUser);

        vm.recordLogs();
        vm.prank(thirdParty);
        pegInContract.resolvePegIn{gas: SETTLE_GAS_BUDGET}(
            rskUser,
            depositTx,
            hex"00",
            RESOLVE_HEIGHT
        );

        assertEq(rskUser.balance - userBefore, BRIDGE_RELEASE);
        _assertSlashed(vm.getRecordedLogs(), collateralBefore);
    }

    function test_unclaimed_deposit_above_size_limit_skips_slash() public {
        _setTierHeader(uint32(T));
        _passClaimWindow();

        _assertSkipped(
            _settle(
                rskUser,
                _depositTxOfSize(rskUser, MAX_SLASHABLE_TX_SIZE + 1)
            )
        );
    }

    function test_unclaimed_settle_at_window_end_skips_slash() public {
        _setTierHeader(uint32(T));
        vm.warp(T + CLAIM_WINDOW);

        _assertSkipped(_settle(rskUser, _defaultTx()));
    }

    function test_unclaimed_settle_window_extended_by_hard_pause() public {
        _setTierHeader(uint32(T));
        vm.warp(T + 10);
        vm.prank(owner);
        pauseRegistry.setPauseLevel(IPauseRegistry.PauseLevel.Hard, "pause");
        vm.warp(T + 110);
        vm.prank(owner);
        pauseRegistry.setPauseLevel(IPauseRegistry.PauseLevel.None, "");

        vm.warp(T + CLAIM_WINDOW + 100);
        _assertSkipped(
            _settle(rskUser, _depositTx(rskUser, DEFAULT_AMOUNT, 1))
        );

        vm.warp(T + CLAIM_WINDOW + 101);
        uint256 collateralBefore = _totalPegInCollateral();
        _assertSlashed(
            _settle(rskUser, _depositTx(rskUser, DEFAULT_AMOUNT, 2)),
            collateralBefore
        );
    }

    function test_unclaimed_settle_hard_pause_before_window_start_does_not_extend()
        public
    {
        _setTierHeader(uint32(T));
        vm.warp(T - 200);
        vm.prank(owner);
        pauseRegistry.setPauseLevel(IPauseRegistry.PauseLevel.Hard, "pause");
        vm.warp(T - 100);
        vm.prank(owner);
        pauseRegistry.setPauseLevel(IPauseRegistry.PauseLevel.None, "");

        _passClaimWindow();
        uint256 collateralBefore = _totalPegInCollateral();
        _assertSlashed(_settle(rskUser, _defaultTx()), collateralBefore);
    }

    function test_unclaimed_settle_window_starts_at_late_registration() public {
        address lateUser = makeAddr("lateUser");
        uint256 registrationBlock = block.number;
        registry.harness_seedRegistration(
            lateUser,
            makeAddr("registrant"),
            uint96(registrationBlock)
        );
        _setTierHeader(uint32(T));
        vm.warp(T + 1 days);

        vm.roll(registrationBlock + 540);
        _assertSkipped(
            _settle(lateUser, _depositTx(lateUser, DEFAULT_AMOUNT, 1))
        );

        vm.roll(registrationBlock + 541);
        uint256 collateralBefore = _totalPegInCollateral();
        _assertSlashed(
            _settle(lateUser, _depositTx(lateUser, DEFAULT_AMOUNT, 2)),
            collateralBefore
        );
    }

    function test_unclaimed_settle_tier_header_unavailable_skips_slash()
        public
    {
        _passClaimWindow();

        _assertSkipped(_settle(rskUser, _defaultTx()));
    }

    function test_unclaimed_settle_pays_user_when_slash_reverts() public {
        vm.prank(owner);
        collateralManagement.setGlobalSlashGraceBlocks(10_000);
        _setTierHeader(uint32(T));
        _passClaimWindow();
        bytes memory depositTx = _defaultTx();
        bytes32 pegInId = _pegInIdForTx(rskUser, depositTx);
        _fund(rskUser);

        vm.expectEmit(true, false, false, false, address(pegInContract));
        emit IPegInCommitFirst.GlobalSlashSkipped(pegInId);
        _resolveAndAssertUserPaid(rskUser, depositTx);

        assertEq(_totalPegInCollateral(), 3 * MIN_COLLATERAL);
    }

    function test_claimed_settle_does_not_slash() public {
        _setTierHeader(uint32(T));
        _claimAndFund(rskUser, _defaultTx(), BRIDGE_RELEASE);
        _passClaimWindow();

        vm.recordLogs();
        _resolve(thirdParty, rskUser, _defaultTx());
        Vm.Log[] memory logs = vm.getRecordedLogs();

        _assertSkipped(logs);
    }

    function test_unclaimed_settle_twice_reverts() public {
        _setTierHeader(uint32(T));
        _passClaimWindow();
        bytes memory depositTx = _defaultTx();
        bytes32 pegInId = _pegInIdForTx(rskUser, depositTx);

        _settle(rskUser, depositTx);
        assertEq(_totalPegInCollateral(), 3 * MIN_COLLATERAL - PENALTY_FEE);

        vm.expectRevert(
            abi.encodeWithSelector(
                IPegInCommitFirst.PegInAlreadyProcessed.selector,
                pegInId
            )
        );
        _resolve(thirdParty, rskUser, depositTx);
    }
}
