// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FlyoverConfigurations} from "../../src/FlyoverConfigurations.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";

/// @title ConfigurationsTestBase
/// @notice Shared setup for the FlyoverConfigurations suite (tests the S2.1 / FLY-2459 contract
/// against the S0-frozen peg-in-only interface). Deploys the contract behind an ERC1967 proxy
/// with a known seed config, explicit deployment bounds, and a non-zero time-lock delay.
/// @dev ERC1967 (not Transparent) is used so `owner` can call admin functions directly; a
/// TransparentUpgradeableProxy would route the admin's calls to the proxy admin, not the impl.
abstract contract ConfigurationsTestBase is Test {
    // --- deployment params ---
    uint48 internal constant ADMIN_DELAY = 0;
    uint256 internal constant TIMELOCK_DELAY = 1 days;

    /// @notice 1 satoshi in wei; fees round down to this boundary.
    uint256 internal constant SAT = 10 ** 10;
    /// @notice Percentage fee denominator: 10_000 == 100%.
    uint256 internal constant PCT_DENOMINATOR = 10_000;

    // --- seed configuration (the active config right after initialize) ---
    uint256 internal constant SEED_FIXED_FEE = 1000 * SAT; // 1e13 wei, satoshi-aligned
    uint256 internal constant SEED_PCT = 10; // 0.10%
    uint256 internal constant SEED_MIN_AMOUNT = 0.001 ether;
    uint256 internal constant SEED_MAX_AMOUNT = 100 ether;

    // --- seed bounds, written at deployment ---
    // fixedFee lower bound IS the 2·D security floor; no queued change may drop below it.
    uint256 internal constant BOUND_MIN_FIXED_FEE = 100 * SAT;
    uint256 internal constant BOUND_MAX_FIXED_FEE = 1 ether;
    uint256 internal constant BOUND_MIN_PCT = 0;
    // Intentionally above the 100% denominator so the InvalidPercentageFee guard is reachable
    // and provably independent of the bound check.
    uint256 internal constant BOUND_MAX_PCT = 20_000;
    uint256 internal constant BOUND_MIN_MIN_AMOUNT = 0;
    uint256 internal constant BOUND_MAX_MIN_AMOUNT = 1 ether;
    uint256 internal constant BOUND_MIN_MAX_AMOUNT = 0;
    uint256 internal constant BOUND_MAX_MAX_AMOUNT = 10_000 ether;

    // --- widened bounds, for the bounds-change tests ---
    // Chosen to strictly contain both the current bounds and the seed config, so applying them
    // is always legal and the widening is observable (values the old bounds rejected pass).
    uint256 internal constant WIDE_MIN_FIXED_FEE = 50 * SAT;
    uint256 internal constant WIDE_MAX_FIXED_FEE = 2 ether;
    uint256 internal constant WIDE_MIN_PCT = 0;
    uint256 internal constant WIDE_MAX_PCT = 30_000;
    uint256 internal constant WIDE_MIN_MIN_AMOUNT = 0;
    uint256 internal constant WIDE_MAX_MIN_AMOUNT = 2 ether;
    uint256 internal constant WIDE_MIN_MAX_AMOUNT = 0;
    uint256 internal constant WIDE_MAX_MAX_AMOUNT = 20_000 ether;

    // --- peg-out seed / bounds ---
    uint256 internal constant SEED_PENALTY_FEE = 0.01 ether;
    uint256 internal constant SEED_CLAIM_WINDOW = 30 minutes;
    uint256 internal constant SEED_CLAIM_WINDOW_BLOCKS = 600;
    uint256 internal constant SEED_CALL_TIME = 2 hours;
    uint256 internal constant SEED_EXPIRE_TIME = 4 hours;
    uint256 internal constant SEED_EXPIRE_BLOCKS = 3_300;
    uint256 internal constant SEED_MAX_MINER_FEE = 0.0005 ether;

    uint256 internal constant BOUND_MIN_PENALTY_FEE = 0.001 ether;
    uint256 internal constant BOUND_MAX_PENALTY_FEE = 1 ether;
    uint256 internal constant BOUND_MIN_CLAIM_WINDOW = 5 minutes;
    uint256 internal constant BOUND_MAX_CLAIM_WINDOW = 1 days;
    uint256 internal constant BOUND_MIN_CLAIM_WINDOW_BLOCKS = 1;
    uint256 internal constant BOUND_MAX_CLAIM_WINDOW_BLOCKS = 50_000;
    uint256 internal constant BOUND_MIN_CALL_TIME = 30 minutes;
    uint256 internal constant BOUND_MAX_CALL_TIME = 2 days;
    uint256 internal constant BOUND_MIN_EXPIRE_TIME = 1 hours;
    uint256 internal constant BOUND_MAX_EXPIRE_TIME = 7 days;
    uint256 internal constant BOUND_MIN_EXPIRE_BLOCKS = 1;
    uint256 internal constant BOUND_MAX_EXPIRE_BLOCKS = 200_000;
    uint256 internal constant BOUND_MIN_MAX_MINER_FEE = 0;
    uint256 internal constant BOUND_MAX_MAX_MINER_FEE = 0.1 ether;

    // ERC-7201 base slot of the mutable namespace `rsk.flyover.FlyoverConfigurations`.
    bytes32 internal constant STORAGE_SLOT =
        0x13aa2a37a5354fe7c5dcced2a6c33933ec66091f98f22792660cd2862f158700;

    // ERC-7201 base slot of the bounds namespace `rsk.flyover.FlyoverConfigurations.bounds`.
    bytes32 internal constant BOUNDS_SLOT =
        0x62f8e0a1022a246e45081dab13f708870be3f38423627ed9d784f6bc5369e500;

    // ERC-7201 base slot of `rsk.flyover.FlyoverConfigurations.pegOut`.
    bytes32 internal constant PEGOUT_STORAGE_SLOT =
        0x15978da28ad46e9b891b8591ece2c0413e91c9a5c9c768c642316e015001be00;

    address internal owner = makeAddr("owner");
    address internal stranger = makeAddr("stranger");

    FlyoverConfigurations internal config;

    function _deploy() internal {
        FlyoverConfigurations impl = new FlyoverConfigurations();
        bytes memory initData = abi.encodeCall(
            FlyoverConfigurations.initialize,
            (
                owner,
                ADMIN_DELAY,
                TIMELOCK_DELAY,
                _seedConfig(),
                _boundsMin(),
                _boundsMax()
            )
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        config = FlyoverConfigurations(payable(address(proxy)));
    }

    function _deployWithPegOut() internal {
        _deploy();
        _initPegOut();
    }

    function _initPegOut() internal {
        vm.prank(owner);
        config.initializePegOut(
            _seedPegOutConfig(),
            _pegOutBoundsMin(),
            _pegOutBoundsMax()
        );
    }

    /// @notice The seed peg-in configuration written at initialize time.
    function _seedConfig()
        internal
        pure
        returns (IFlyoverConfigurations.PegConfiguration memory c)
    {
        c.fixedFee = SEED_FIXED_FEE;
        c.percentageFee = SEED_PCT;
        c.minAmount = SEED_MIN_AMOUNT;
        c.maxAmount = SEED_MAX_AMOUNT;
        c.confirmationTiers = _seedTiers();
    }

    /// @notice Seed tiers: (1e18,1) (10e18,3) (100e18,6), strictly ascending.
    function _seedTiers()
        internal
        pure
        returns (IFlyoverConfigurations.ConfirmationTier[] memory tiers)
    {
        tiers = new IFlyoverConfigurations.ConfirmationTier[](3);
        tiers[0] = IFlyoverConfigurations.ConfirmationTier({
            maxAmount: 1 ether,
            confirmations: 1
        });
        tiers[1] = IFlyoverConfigurations.ConfirmationTier({
            maxAmount: 10 ether,
            confirmations: 3
        });
        tiers[2] = IFlyoverConfigurations.ConfirmationTier({
            maxAmount: 100 ether,
            confirmations: 6
        });
    }

    function _boundsMin()
        internal
        pure
        returns (IFlyoverConfigurations.PegConfiguration memory c)
    {
        c.fixedFee = BOUND_MIN_FIXED_FEE;
        c.percentageFee = BOUND_MIN_PCT;
        c.minAmount = BOUND_MIN_MIN_AMOUNT;
        c.maxAmount = BOUND_MIN_MAX_AMOUNT;
        // Tier array is ordering/non-emptiness checked, never min/max bounded; left empty.
        c.confirmationTiers = new IFlyoverConfigurations.ConfirmationTier[](0);
    }

    function _boundsMax()
        internal
        pure
        returns (IFlyoverConfigurations.PegConfiguration memory c)
    {
        c.fixedFee = BOUND_MAX_FIXED_FEE;
        c.percentageFee = BOUND_MAX_PCT;
        c.minAmount = BOUND_MAX_MIN_AMOUNT;
        c.maxAmount = BOUND_MAX_MAX_AMOUNT;
        c.confirmationTiers = new IFlyoverConfigurations.ConfirmationTier[](0);
    }

    /// @notice A valid config distinct from the seed, for queue/apply tests so the applied change
    /// is observable. All scalars sit within the deployment bounds.
    function _altConfig()
        internal
        pure
        returns (IFlyoverConfigurations.PegConfiguration memory c)
    {
        c.fixedFee = 2000 * SAT;
        c.percentageFee = 20; // 0.20%
        c.minAmount = 0.002 ether;
        c.maxAmount = 200 ether;
        c.confirmationTiers = new IFlyoverConfigurations.ConfirmationTier[](2);
        c.confirmationTiers[0] = IFlyoverConfigurations.ConfirmationTier({
            maxAmount: 2 ether,
            confirmations: 2
        });
        c.confirmationTiers[1] = IFlyoverConfigurations.ConfirmationTier({
            maxAmount: 20 ether,
            confirmations: 5
        });
    }

    /// @notice Convenience: queue `_altConfig()` as the admin and return it.
    function _queueAlt()
        internal
        returns (IFlyoverConfigurations.PegConfiguration memory c)
    {
        c = _altConfig();
        vm.prank(owner);
        config.queueChange(c);
    }

    // ------------------------------------------------------------------ bounds-change helpers

    /// @notice Widened lower bounds: strictly below the deployment min on every field.
    function _wideMin()
        internal
        pure
        returns (IFlyoverConfigurations.PegConfiguration memory c)
    {
        c.fixedFee = WIDE_MIN_FIXED_FEE;
        c.percentageFee = WIDE_MIN_PCT;
        c.minAmount = WIDE_MIN_MIN_AMOUNT;
        c.maxAmount = WIDE_MIN_MAX_AMOUNT;
        c.confirmationTiers = new IFlyoverConfigurations.ConfirmationTier[](0);
    }

    /// @notice Widened upper bounds: strictly above the deployment max on every field.
    function _wideMax()
        internal
        pure
        returns (IFlyoverConfigurations.PegConfiguration memory c)
    {
        c.fixedFee = WIDE_MAX_FIXED_FEE;
        c.percentageFee = WIDE_MAX_PCT;
        c.minAmount = WIDE_MAX_MIN_AMOUNT;
        c.maxAmount = WIDE_MAX_MAX_AMOUNT;
        c.confirmationTiers = new IFlyoverConfigurations.ConfirmationTier[](0);
    }

    /// @notice Convenience: queue the widened bounds as the admin.
    function _queueWideBounds() internal {
        vm.prank(owner);
        config.queueBoundsChange(_wideMin(), _wideMax());
    }

    /// @notice Queue a bounds pair as the admin, wait the delay, and apply it.
    function _applyBounds(
        IFlyoverConfigurations.PegConfiguration memory min,
        IFlyoverConfigurations.PegConfiguration memory max
    ) internal {
        vm.prank(owner);
        config.queueBoundsChange(min, max);
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(owner);
        config.applyBoundsChange();
    }

    /// @notice Queue a configuration as the admin, wait the delay, and apply it.
    function _applyConfig(
        IFlyoverConfigurations.PegConfiguration memory c
    ) internal {
        vm.prank(owner);
        config.queueChange(c);
        vm.warp(block.timestamp + TIMELOCK_DELAY);
        vm.prank(owner);
        config.applyChange();
    }

    function _seedPegOutConfig()
        internal
        pure
        returns (IFlyoverConfigurations.PegOutConfiguration memory c)
    {
        c.fixedFee = SEED_FIXED_FEE;
        c.percentageFee = SEED_PCT;
        c.minAmount = SEED_MIN_AMOUNT;
        c.maxAmount = SEED_MAX_AMOUNT;
        c.confirmationTiers = _seedTiers();
        c.penaltyFee = SEED_PENALTY_FEE;
        c.claimWindow = SEED_CLAIM_WINDOW;
        c.claimWindowBlocks = SEED_CLAIM_WINDOW_BLOCKS;
        c.callTime = SEED_CALL_TIME;
        c.expireTime = SEED_EXPIRE_TIME;
        c.expireBlocks = SEED_EXPIRE_BLOCKS;
        c.maxMinerFee = SEED_MAX_MINER_FEE;
    }

    function _pegOutBoundsMin()
        internal
        pure
        returns (IFlyoverConfigurations.PegOutConfiguration memory c)
    {
        c.fixedFee = BOUND_MIN_FIXED_FEE;
        c.percentageFee = BOUND_MIN_PCT;
        c.minAmount = BOUND_MIN_MIN_AMOUNT;
        c.maxAmount = BOUND_MIN_MAX_AMOUNT;
        c.confirmationTiers = new IFlyoverConfigurations.ConfirmationTier[](0);
        c.penaltyFee = BOUND_MIN_PENALTY_FEE;
        c.claimWindow = BOUND_MIN_CLAIM_WINDOW;
        c.claimWindowBlocks = BOUND_MIN_CLAIM_WINDOW_BLOCKS;
        c.callTime = BOUND_MIN_CALL_TIME;
        c.expireTime = BOUND_MIN_EXPIRE_TIME;
        c.expireBlocks = BOUND_MIN_EXPIRE_BLOCKS;
        c.maxMinerFee = BOUND_MIN_MAX_MINER_FEE;
    }

    function _pegOutBoundsMax()
        internal
        pure
        returns (IFlyoverConfigurations.PegOutConfiguration memory c)
    {
        c.fixedFee = BOUND_MAX_FIXED_FEE;
        c.percentageFee = BOUND_MAX_PCT;
        c.minAmount = BOUND_MAX_MIN_AMOUNT;
        c.maxAmount = BOUND_MAX_MAX_AMOUNT;
        c.confirmationTiers = new IFlyoverConfigurations.ConfirmationTier[](0);
        c.penaltyFee = BOUND_MAX_PENALTY_FEE;
        c.claimWindow = BOUND_MAX_CLAIM_WINDOW;
        c.claimWindowBlocks = BOUND_MAX_CLAIM_WINDOW_BLOCKS;
        c.callTime = BOUND_MAX_CALL_TIME;
        c.expireTime = BOUND_MAX_EXPIRE_TIME;
        c.expireBlocks = BOUND_MAX_EXPIRE_BLOCKS;
        c.maxMinerFee = BOUND_MAX_MAX_MINER_FEE;
    }

    function _altPegOutConfig()
        internal
        pure
        returns (IFlyoverConfigurations.PegOutConfiguration memory c)
    {
        c.fixedFee = 2000 * SAT;
        c.percentageFee = 20;
        c.minAmount = 0.002 ether;
        c.maxAmount = 200 ether;
        c.confirmationTiers = new IFlyoverConfigurations.ConfirmationTier[](2);
        c.confirmationTiers[0] = IFlyoverConfigurations.ConfirmationTier({
            maxAmount: 2 ether,
            confirmations: 2
        });
        c.confirmationTiers[1] = IFlyoverConfigurations.ConfirmationTier({
            maxAmount: 20 ether,
            confirmations: 5
        });
        c.penaltyFee = 0.02 ether;
        c.claimWindow = 45 minutes;
        c.claimWindowBlocks = 900;
        c.callTime = 3 hours;
        c.expireTime = 5 hours;
        c.expireBlocks = 4_000;
        c.maxMinerFee = 0.001 ether;
    }

    function _queueAltPegOut()
        internal
        returns (IFlyoverConfigurations.PegOutConfiguration memory c)
    {
        c = _altPegOutConfig();
        vm.prank(owner);
        config.queuePegOutChange(c);
    }
}
