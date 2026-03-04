// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {HandlerBase} from "./HandlerBase.sol";
import {PegOutContract} from "../../../src/PegOutContract.sol";
import {PegInContract} from "../../../src/PegInContract.sol";
import {CollateralManagementContract} from "../../../src/CollateralManagement.sol";
import {FlyoverDiscovery} from "../../../src/FlyoverDiscovery.sol";
import {Quotes} from "../../../src/libraries/Quotes.sol";
import {Flyover} from "../../../src/libraries/Flyover.sol";

/// @title System Invariant Handler
/// @notice Cross-contract handler for full system invariant testing
contract SystemHandler is HandlerBase {
    PegOutContract public pegOutContract;
    PegInContract public pegInContract;
    CollateralManagementContract public collateralManagement;
    FlyoverDiscovery public discovery;

    address public adder;

    struct ProviderInfo {
        address addr;
        uint256 privateKey;
        uint256 providerId;
        Flyover.ProviderType providerType;
        bool resigned;
    }

    ProviderInfo[] public providers;
    bytes32[] public activePegOutQuoteHashes;

    uint256 public ghost_totalCollateralAdded;
    uint256 public ghost_totalSlashed;
    uint256 public ghost_totalCollateralWithdrawn;
    uint256 public ghost_totalPegInDeposited;
    uint256 public ghost_totalPegInWithdrawn;
    uint256 public ghost_totalPegOutDeposited;
    uint256 public ghost_totalPegOutRefunded;
    uint256 public ghost_totalPegOutWithdrawn;
    uint256 public ghost_totalRewardsWithdrawn;
    uint256 public ghost_totalETHIn;

    uint256 private _nonce;

    Quotes.PegOutQuote internal _staged;
    uint256 private _stagedKey;
    bytes private _stagedSignature;
    mapping(bytes32 => Quotes.PegOutQuote) internal _storedQuotes;

    Quotes.PegInQuote internal _stagedPegInSlash;
    Quotes.PegOutQuote internal _stagedPegOutSlash;

    address public user;
    address public punisher;
    address public slasher;

    constructor(
        PegOutContract pegOutContract_,
        PegInContract pegInContract_,
        CollateralManagementContract collateralManagement_,
        FlyoverDiscovery discovery_,
        address adder_,
        address slasher_,
        address user_,
        address punisher_
    ) {
        pegOutContract = pegOutContract_;
        pegInContract = pegInContract_;
        collateralManagement = collateralManagement_;
        discovery = discovery_;
        adder = adder_;
        slasher = slasher_;
        user = user_;
        punisher = punisher_;
    }

    // ============ Handlers ============

    function registerProvider(
        uint256 seed,
        uint8 typeSeed,
        uint256 extraCollateral
    ) external {
        handlerCalls["registerProvider"] += 1;

        Flyover.ProviderType pType = _getProviderType(typeSeed);
        uint256 required = _getRequiredCollateral(pType);
        extraCollateral = bound(extraCollateral, 0, 3 ether);
        uint256 collateral = required + extraCollateral;

        _nonce++;
        (address provAddr, uint256 privKey) = makeAddrAndKey(
            string(
                abi.encodePacked(
                    "sys-provider-",
                    vm.toString(seed),
                    "-",
                    vm.toString(_nonce)
                )
            )
        );
        vm.deal(provAddr, collateral + 1 ether);

        string memory name = _generateName(_nonce);
        string memory url = _generateUrl(_nonce);

        vm.prank(provAddr, provAddr);
        try
            discovery.register{value: collateral}(name, url, true, pType)
        returns (uint256 id) {
            providers.push(
                ProviderInfo({
                    addr: provAddr,
                    privateKey: privKey,
                    providerId: id,
                    providerType: pType,
                    resigned: false
                })
            );
            ghost_totalCollateralAdded += collateral;
            ghost_totalETHIn += collateral;
        } catch {}
    }

    function addMoreCollateral(
        uint256 providerSeed,
        uint256 amount,
        bool pegIn
    ) external {
        handlerCalls["addMoreCollateral"] += 1;
        if (providers.length == 0) return;

        ProviderInfo storage info = providers[providerSeed % providers.length];
        if (info.resigned) return;

        amount = bound(amount, 0.1 ether, 5 ether);
        vm.deal(adder, amount);

        vm.prank(adder);
        if (pegIn) {
            try
                collateralManagement.addPegInCollateralTo{value: amount}(
                    info.addr
                )
            {
                ghost_totalCollateralAdded += amount;
                ghost_totalETHIn += amount;
            } catch {}
        } else {
            try
                collateralManagement.addPegOutCollateralTo{value: amount}(
                    info.addr
                )
            {
                ghost_totalCollateralAdded += amount;
                ghost_totalETHIn += amount;
            } catch {}
        }
    }

    function pegInDeposit(uint256 providerSeed, uint256 amount) external {
        handlerCalls["pegInDeposit"] += 1;
        ProviderInfo memory info = _getProviderByType(providerSeed, true);
        if (info.addr == address(0)) return;

        amount = bound(amount, 0.01 ether, 5 ether);
        vm.deal(info.addr, amount);
        vm.prank(info.addr);
        try pegInContract.deposit{value: amount}() {
            ghost_totalPegInDeposited += amount;
            ghost_totalETHIn += amount;
        } catch {}
    }

    function pegInWithdraw(uint256 providerSeed, uint256 amount) external {
        handlerCalls["pegInWithdraw"] += 1;
        ProviderInfo memory info = _getProviderByType(providerSeed, true);
        if (info.addr == address(0)) return;

        uint256 balance = pegInContract.getBalance(info.addr);
        if (balance == 0) return;
        amount = bound(amount, 1, balance);

        vm.prank(info.addr);
        try pegInContract.withdraw(amount) {
            ghost_totalPegInWithdrawn += amount;
        } catch {}
    }

    function pegOutDeposit(uint256 providerSeed, uint256 value) external {
        handlerCalls["pegOutDeposit"] += 1;
        ProviderInfo memory info = _getProviderByType(providerSeed, false);
        if (info.addr == address(0)) return;

        value = bound(value, 0.01 ether, 5 ether);
        _nonce++;
        _stagePegOutDepositQuote(
            _staged,
            info.addr,
            value,
            address(pegOutContract),
            user,
            _nonce
        );
        _stagedKey = info.privateKey;

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
        vm.deal(user, totalValue);
        vm.prank(user);
        pegOutContract.depositPegOut{value: totalValue}(
            _staged,
            _stagedSignature
        );

        ghost_totalPegOutDeposited += totalValue;
        ghost_totalETHIn += totalValue;

        bytes32 quoteHash = pegOutContract.hashPegOutQuote(_staged);
        _pruneCompletedQuotes(8);
        activePegOutQuoteHashes.push(quoteHash);
        _storedQuotes[quoteHash] = _staged;
    }

    function refundUserPegOut(uint256 quoteSeed) external {
        handlerCalls["refundUserPegOut"] += 1;
        if (activePegOutQuoteHashes.length == 0) return;

        uint256 idx = quoteSeed % activePegOutQuoteHashes.length;
        bytes32 quoteHash = activePegOutQuoteHashes[idx];

        if (pegOutContract.isQuoteCompleted(quoteHash)) {
            delete _storedQuotes[quoteHash];
            _removeFromArray(activePegOutQuoteHashes, idx);
            return;
        }

        Quotes.PegOutQuote storage quote = _storedQuotes[quoteHash];
        _advanceToQuoteExpiry(quote);

        uint256 refundAmount = quote.value + quote.callFee + quote.gasFee;
        uint256 preSlashCollateral = collateralManagement.getPegOutCollateral(
            quote.lpRskAddress
        );

        vm.prank(user);
        try pegOutContract.refundUserPegOut(quoteHash) {
            ghost_totalPegOutRefunded += refundAmount;
            uint256 postSlashCollateral = collateralManagement
                .getPegOutCollateral(quote.lpRskAddress);
            if (preSlashCollateral > postSlashCollateral) {
                ghost_totalSlashed += (preSlashCollateral -
                    postSlashCollateral);
            }
            delete _storedQuotes[quoteHash];
            _removeFromArray(activePegOutQuoteHashes, idx);
        } catch {}
    }

    function pegOutWithdraw(uint256 providerSeed, uint256 amount) external {
        handlerCalls["pegOutWithdraw"] += 1;
        ProviderInfo memory info = _getProviderByType(providerSeed, false);
        if (info.addr == address(0)) return;

        uint256 balance = pegOutContract.getBalance(info.addr);
        if (balance == 0) return;
        amount = bound(amount, 1, balance);

        vm.prank(info.addr);
        try pegOutContract.withdraw(payable(info.addr), amount) {
            ghost_totalPegOutWithdrawn += amount;
        } catch {}
    }

    function resign(uint256 providerSeed) external {
        handlerCalls["resign"] += 1;
        if (providers.length == 0) return;

        ProviderInfo storage info = providers[providerSeed % providers.length];
        if (info.resigned) return;

        uint256 pegIn = collateralManagement.getPegInCollateral(info.addr);
        uint256 pegOut = collateralManagement.getPegOutCollateral(info.addr);
        if (pegIn == 0 && pegOut == 0) return;

        vm.prank(info.addr);
        try collateralManagement.resign() {
            info.resigned = true;
        } catch {}
    }

    function withdrawCollateral(uint256 providerSeed) external {
        handlerCalls["withdrawCollateral"] += 1;
        if (providers.length == 0) return;

        ProviderInfo storage info = providers[providerSeed % providers.length];
        if (!info.resigned) return;

        vm.roll(block.number + RESIGN_DELAY + 1);

        uint256 pegIn = collateralManagement.getPegInCollateral(info.addr);
        uint256 pegOut = collateralManagement.getPegOutCollateral(info.addr);

        vm.prank(info.addr);
        try collateralManagement.withdrawCollateral() {
            ghost_totalCollateralWithdrawn += pegIn + pegOut;
        } catch {}
    }

    function slashPegIn(uint256 providerSeed, uint256 penaltyFee) external {
        handlerCalls["slashPegIn"] += 1;
        if (providers.length == 0) return;

        address provider = providers[providerSeed % providers.length].addr;
        uint256 collateral = collateralManagement.getPegInCollateral(provider);
        if (collateral == 0) return;

        penaltyFee = bound(penaltyFee, 1, collateral);
        _nonce++;

        _stagePegInQuote(
            _stagedPegInSlash,
            provider,
            penaltyFee,
            address(collateralManagement)
        );

        vm.prank(slasher);
        try
            collateralManagement.slashPegInCollateral(
                punisher,
                _stagedPegInSlash,
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

        address provider = providers[providerSeed % providers.length].addr;
        uint256 collateral = collateralManagement.getPegOutCollateral(provider);
        if (collateral == 0) return;

        penaltyFee = bound(penaltyFee, 1, collateral);
        _nonce++;

        _stagePegOutSlashQuote(
            _stagedPegOutSlash,
            provider,
            penaltyFee,
            address(collateralManagement)
        );

        vm.prank(slasher);
        try
            collateralManagement.slashPegOutCollateral(
                punisher,
                _stagedPegOutSlash,
                bytes32(_nonce)
            )
        {
            uint256 postSlashCollateral = collateralManagement
                .getPegOutCollateral(provider);
            ghost_totalSlashed += (collateral - postSlashCollateral);
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

    function setProviderStatus(uint256 providerSeed, bool status) external {
        handlerCalls["setProviderStatus"] += 1;
        if (providers.length == 0) return;

        ProviderInfo storage info = providers[providerSeed % providers.length];
        vm.prank(info.addr);
        try discovery.setProviderStatus(info.providerId, status) {} catch {}
    }

    function advanceTime(uint256 blocks, uint256 seconds_) external {
        handlerCalls["advanceTime"] += 1;
        blocks = bound(blocks, 1, 100);
        seconds_ = bound(seconds_, 1, 7200);
        vm.roll(block.number + blocks);
        vm.warp(block.timestamp + seconds_);
    }

    // ============ View Helpers ============

    function getProviderCount() external view returns (uint256) {
        return providers.length;
    }

    function getProviderAddr(uint256 idx) external view returns (address) {
        return providers[idx].addr;
    }

    function getProviderType(
        uint256 idx
    ) external view returns (Flyover.ProviderType) {
        return providers[idx].providerType;
    }

    function isProviderResigned(uint256 idx) external view returns (bool) {
        return providers[idx].resigned;
    }

    function getActiveQuoteCount() external view returns (uint256) {
        return activePegOutQuoteHashes.length;
    }

    // ============ Internal Helpers ============

    /// @dev Finds a non-resigned provider matching PegIn (isPegIn=true) or PegOut (isPegIn=false)
    function _getProviderByType(
        uint256 seed,
        bool isPegIn
    ) internal view returns (ProviderInfo memory) {
        if (providers.length == 0)
            return
                ProviderInfo(
                    address(0),
                    0,
                    0,
                    Flyover.ProviderType.PegIn,
                    false
                );
        uint256 start = seed % providers.length;
        for (uint256 i = 0; i < providers.length; i++) {
            uint256 idx = (start + i) % providers.length;
            if (providers[idx].resigned) continue;
            Flyover.ProviderType t = providers[idx].providerType;
            if (
                isPegIn &&
                (t == Flyover.ProviderType.PegIn ||
                    t == Flyover.ProviderType.Both)
            ) {
                return providers[idx];
            }
            if (
                !isPegIn &&
                (t == Flyover.ProviderType.PegOut ||
                    t == Flyover.ProviderType.Both)
            ) {
                return providers[idx];
            }
        }
        return
            ProviderInfo(address(0), 0, 0, Flyover.ProviderType.PegIn, false);
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
        while (i < activePegOutQuoteHashes.length && maxScan > 0) {
            bytes32 quoteHash = activePegOutQuoteHashes[i];
            if (pegOutContract.isQuoteCompleted(quoteHash)) {
                delete _storedQuotes[quoteHash];
                _removeFromArray(activePegOutQuoteHashes, i);
            } else {
                i++;
            }
            maxScan--;
        }
    }
}
