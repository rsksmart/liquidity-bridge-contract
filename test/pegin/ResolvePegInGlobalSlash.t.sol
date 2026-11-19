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
