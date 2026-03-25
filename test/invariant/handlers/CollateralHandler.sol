// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {HandlerBase} from "./HandlerBase.sol";
import {CollateralManagementContract} from "../../../src/CollateralManagement.sol";
import {Quotes} from "../../../src/libraries/Quotes.sol";

/// @title Collateral Invariant Handler
/// @notice Provides fuzzable handler functions for CollateralManagement invariant testing
contract CollateralHandler is HandlerBase {
    CollateralManagementContract public collateralManagement;

    address public adder;
    address public slasher;
    address public punisher;

    address[] public providers;

    uint256 public ghost_totalAdded;
    uint256 public ghost_totalSlashed;
    uint256 public ghost_totalWithdrawn;
    uint256 public ghost_totalRewardsWithdrawn;

    uint256 private _nonce;

    Quotes.PegInQuote internal _stagedPegInQuote;
    Quotes.PegOutQuote internal _stagedPegOutQuote;

    constructor(
        CollateralManagementContract collateralManagement_,
        address adder_,
        address slasher_,
        address punisher_
    ) {
        collateralManagement = collateralManagement_;
        adder = adder_;
        slasher = slasher_;
        punisher = punisher_;
    }

    function addPegInCollateral(uint256 providerSeed, uint256 amount) external {
        handlerCalls["addPegInCollateral"] += 1;
        amount = bound(amount, MIN_COLLATERAL, 10 ether);
        address provider = _getOrCreateProvider(providerSeed);

        vm.deal(adder, amount);
        vm.prank(adder);
        collateralManagement.addPegInCollateralTo{value: amount}(provider);

        ghost_totalAdded += amount;
    }

    function addPegOutCollateral(
        uint256 providerSeed,
        uint256 amount
    ) external {
        handlerCalls["addPegOutCollateral"] += 1;
        amount = bound(amount, MIN_COLLATERAL, 10 ether);
        address provider = _getOrCreateProvider(providerSeed);

        vm.deal(adder, amount);
        vm.prank(adder);
        collateralManagement.addPegOutCollateralTo{value: amount}(provider);

        ghost_totalAdded += amount;
    }

    function slashPegIn(uint256 providerSeed, uint256 penaltyFee) external {
        handlerCalls["slashPegIn"] += 1;
        if (providers.length == 0) return;

        address provider = providers[providerSeed % providers.length];
        uint256 collateral = collateralManagement.getPegInCollateral(provider);
        if (collateral == 0) return;

        penaltyFee = bound(penaltyFee, 1, collateral);
        _nonce++;

        _stagePegInQuote(
            _stagedPegInQuote,
            provider,
            penaltyFee,
            address(collateralManagement)
        );

        vm.prank(slasher);
        try
            collateralManagement.slashPegInCollateral(
                punisher,
                _stagedPegInQuote,
                bytes32(_nonce)
            )
        {
            uint256 postSlashCollateral = collateralManagement
                .getPegInCollateral(provider);
            ghost_totalSlashed += (collateral - postSlashCollateral);
        } catch {}
    }

    function slashPegOut(uint256 providerSeed, uint256 penaltyFee) external {
        handlerCalls["slashPegOut"] += 1;
        if (providers.length == 0) return;

        address provider = providers[providerSeed % providers.length];
        uint256 collateral = collateralManagement.getPegOutCollateral(provider);
        if (collateral == 0) return;

        penaltyFee = bound(penaltyFee, 1, collateral);
        _nonce++;

        _stagePegOutSlashQuote(
            _stagedPegOutQuote,
            provider,
            penaltyFee,
            address(collateralManagement)
        );

        vm.prank(slasher);
        try
            collateralManagement.slashPegOutCollateral(
                punisher,
                _stagedPegOutQuote,
                bytes32(_nonce)
            )
        {
            uint256 postSlashCollateral = collateralManagement
                .getPegOutCollateral(provider);
            ghost_totalSlashed += (collateral - postSlashCollateral);
        } catch {}
    }

    function resignAndWithdraw(uint256 providerSeed) external {
        handlerCalls["resignAndWithdraw"] += 1;
        if (providers.length == 0) return;

        address provider = providers[providerSeed % providers.length];
        uint256 pegIn = collateralManagement.getPegInCollateral(provider);
        uint256 pegOut = collateralManagement.getPegOutCollateral(provider);
        if (pegIn == 0 && pegOut == 0) return;

        vm.prank(provider);
        try collateralManagement.resign() {} catch {
            return;
        }

        vm.roll(block.number + RESIGN_DELAY + 1);

        uint256 totalCollateral = pegIn + pegOut;
        vm.prank(provider);
        try collateralManagement.withdrawCollateral() {
            ghost_totalWithdrawn += totalCollateral;
        } catch {}
    }

    function withdrawRewards() external {
        handlerCalls["withdrawRewards"] += 1;

        uint256 rewards = collateralManagement.getRewards(punisher);
        if (rewards == 0) return;

        vm.prank(punisher);
        try collateralManagement.withdrawRewards() {
            ghost_totalRewardsWithdrawn += rewards;
        } catch {}
    }

    function getProviderCount() external view returns (uint256) {
        return providers.length;
    }

    function getProvider(uint256 idx) external view returns (address) {
        return providers[idx];
    }

    function _getOrCreateProvider(
        uint256 seed
    ) internal returns (address provider) {
        if (providers.length > 0 && seed % 3 != 0) {
            return providers[seed % providers.length];
        }

        provider = address(
            uint160(uint256(keccak256(abi.encode(seed, providers.length))))
        );
        providers.push(provider);
        vm.deal(provider, 10 ether);
        return provider;
    }
}
