// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {HandlerBase} from "./HandlerBase.sol";
import {PegOutContract} from "../../../src/PegOutContract.sol";
import {CollateralManagementContract} from "../../../src/CollateralManagement.sol";
import {FlyoverDiscovery} from "../../../src/FlyoverDiscovery.sol";
import {Quotes} from "../../../src/libraries/Quotes.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";

/// @title PegOut Invariant Handler
/// @notice Provides fuzzable handler functions for PegOutContract invariant testing
contract PegOutHandler is HandlerBase {
    PegOutContract public pegOutContract;
    CollateralManagementContract public collateralManagement;
    FlyoverDiscovery public discovery;

    address public user;

    struct LPInfo {
        address addr;
        uint256 privateKey;
        Flyover.ProviderType providerType;
    }

    LPInfo[] public lps;
    bytes32[] public activeQuoteHashes;
    mapping(bytes32 => Quotes.PegOutQuote) internal storedQuotes;

    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalRefunded;
    uint256 public ghost_totalWithdrawn;
    uint256 public ghost_totalSlashed;
    uint256 public ghost_totalRetainedDust;

    uint256 private _nonce;

    Quotes.PegOutQuote private _staged;
    uint256 private _stagedKey;
    bytes private _stagedSignature;
    uint256 private _stagedOverpay;

    constructor(
        PegOutContract pegOutContract_,
        CollateralManagementContract collateralManagement_,
        FlyoverDiscovery discovery_,
        address user_
    ) {
        pegOutContract = pegOutContract_;
        collateralManagement = collateralManagement_;
        discovery = discovery_;
        user = user_;
    }

    function addLP(
        address addr,
        uint256 privateKey,
        Flyover.ProviderType providerType
    ) external {
        lps.push(
            LPInfo({
                addr: addr,
                privateKey: privateKey,
                providerType: providerType
            })
        );
    }

    function depositPegOut(
        uint256 lpSeed,
        uint256 value,
        uint256 overpay
    ) external {
        handlerCalls["depositPegOut"] += 1;

        LPInfo memory lp = _getPegOutLP(lpSeed);
        if (lp.addr == address(0)) return;

        value = bound(value, 0.01 ether, 5 ether);
        _nonce++;
        _stagePegOutDepositQuote(
            _staged,
            lp.addr,
            value,
            address(pegOutContract),
            user,
            _nonce
        );
        _stagedKey = lp.privateKey;
        uint256 dustThreshold = pegOutContract.dustThreshold();
        if (dustThreshold > 0) {
            _stagedOverpay = bound(overpay, 0, dustThreshold - 1);
        } else {
            _stagedOverpay = 0;
        }

        try this.executeDeposit() {} catch {}
    }

    function executeDeposit() external {
        this.signStaged();
        this.submitStaged();
    }

    function signStaged() external {
        bytes32 eip712Hash = pegOutContract.hashPegOutQuoteEIP712(_staged);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_stagedKey, eip712Hash);
        _stagedSignature = abi.encodePacked(r, s, v);
    }

    function submitStaged() external {
        uint256 totalValue = _staged.value + _staged.callFee + _staged.gasFee;
        uint256 paidAmount = totalValue + _stagedOverpay;
        vm.deal(user, paidAmount);
        vm.prank(user);
        pegOutContract.depositPegOut{value: paidAmount}(
            _staged,
            _stagedSignature
        );

        ghost_totalDeposited += paidAmount;
        ghost_totalRetainedDust += _stagedOverpay;
        _stagedOverpay = 0;

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(_staged);
        _pruneCompletedQuotes(8);
        activeQuoteHashes.push(quoteHash);
        storedQuotes[quoteHash] = _staged;
    }

    function refundUserPegOut(uint256 quoteSeed) external {
        handlerCalls["refundUserPegOut"] += 1;

        if (activeQuoteHashes.length == 0) return;

        uint256 idx = quoteSeed % activeQuoteHashes.length;
        bytes32 quoteHash = activeQuoteHashes[idx];

        if (pegOutContract.isQuoteCompleted(quoteHash)) {
            delete storedQuotes[quoteHash];
            _removeFromArray(activeQuoteHashes, idx);
            return;
        }

        Quotes.PegOutQuote storage quote = storedQuotes[quoteHash];
        uint256 preSlashCollateral = collateralManagement.getPegOutCollateral(
            quote.lpRskAddress
        );

        _advanceToQuoteExpiry(quote);

        uint256 refundAmount = quote.value + quote.callFee + quote.gasFee;

        vm.prank(user);
        try pegOutContract.refundUserPegOut(quoteHash) {
            ghost_totalRefunded += refundAmount;
            uint256 postSlashCollateral = collateralManagement
                .getPegOutCollateral(quote.lpRskAddress);
            if (preSlashCollateral > postSlashCollateral) {
                ghost_totalSlashed += (preSlashCollateral -
                    postSlashCollateral);
            }
            delete storedQuotes[quoteHash];
            _removeFromArray(activeQuoteHashes, idx);
        } catch {}
    }

    function lpWithdraw(uint256 lpSeed, uint256 amount) external {
        handlerCalls["lpWithdraw"] += 1;

        if (lps.length == 0) return;
        LPInfo memory lp = lps[lpSeed % lps.length];

        uint256 balance = pegOutContract.getBalance(lp.addr);
        if (balance == 0) return;

        amount = bound(amount, 1, balance);

        vm.prank(lp.addr);
        try pegOutContract.withdraw(payable(lp.addr), amount) {
            ghost_totalWithdrawn += amount;
        } catch {}
    }

    function getActiveQuoteCount() external view returns (uint256) {
        return activeQuoteHashes.length;
    }

    function getLPCount() external view returns (uint256) {
        return lps.length;
    }

    function calculateActiveLiability() external view returns (uint256 total) {
        for (uint256 i = 0; i < activeQuoteHashes.length; i++) {
            bytes32 quoteHash = activeQuoteHashes[i];
            if (pegOutContract.isQuoteCompleted(quoteHash)) continue;
            Quotes.PegOutQuote storage quote = storedQuotes[quoteHash];
            total += quote.value + quote.callFee + quote.gasFee;
        }
    }

    function _getPegOutLP(uint256 seed) internal view returns (LPInfo memory) {
        if (lps.length == 0)
            return LPInfo(address(0), 0, Flyover.ProviderType.PegIn);

        uint256 startIdx = seed % lps.length;
        for (uint256 i = 0; i < lps.length; i++) {
            uint256 idx = (startIdx + i) % lps.length;
            if (
                lps[idx].providerType == Flyover.ProviderType.PegOut ||
                lps[idx].providerType == Flyover.ProviderType.Both
            ) {
                return lps[idx];
            }
        }
        return LPInfo(address(0), 0, Flyover.ProviderType.PegIn);
    }

    function _advanceToQuoteExpiry(Quotes.PegOutQuote storage quote) internal {
        uint256 targetTs = uint256(quote.expireDate) + 1;
        uint256 targetBlock = uint256(quote.expireBlock) + 1;
        if (targetTs > block.timestamp) {
            vm.warp(targetTs);
        }
        if (targetBlock > block.number) {
            vm.roll(targetBlock);
        }
    }

    function _pruneCompletedQuotes(uint256 maxScan) internal {
        uint256 i = 0;
        while (i < activeQuoteHashes.length && maxScan > 0) {
            bytes32 quoteHash = activeQuoteHashes[i];
            if (pegOutContract.isQuoteCompleted(quoteHash)) {
                delete storedQuotes[quoteHash];
                _removeFromArray(activeQuoteHashes, i);
            } else {
                i++;
            }
            maxScan--;
        }
    }
}
