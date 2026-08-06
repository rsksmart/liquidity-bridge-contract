// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {EmergencyPause} from "./EmergencyPause/EmergencyPause.sol";
import {ICollateralManagement, CollateralManagementSet} from "./interfaces/ICollateralManagement.sol";
import {IFlyoverConfigurations} from "./interfaces/IFlyoverConfigurations.sol";
import {IPauseRegistry} from "./interfaces/IPauseRegistry.sol";
import {IPegOut} from "./interfaces/IPegOut.sol";
import {IPegOutEscrow} from "./interfaces/IPegOutEscrow.sol";
import {Flyover} from "./libraries/Flyover.sol";
import {Quotes} from "./libraries/Quotes.sol";

/// @dev Narrow read of PegOutContract's public dust threshold (avoid concrete import).
interface IDustThreshold {
    function dustThreshold() external view returns (uint256);
}

/// @title PegOutEscrow
/// @notice Commit-first peg-out escrow (PoC). User deposits RBTC first; LPs claim and settle
/// via PegOutContract. Fee / deadline parameters are read from {IFlyoverConfigurations}.
/// @author Rootstock Labs
contract PegOutEscrow is
    AccessControlDefaultAdminRulesUpgradeable,
    EmergencyPause,
    ReentrancyGuard,
    IPegOutEscrow
{
    /// @custom:storage-location erc7201:rsk.flyover.PegOutEscrow
    struct PegOutEscrowStorage {
        IPegOut pegOutContract;
        ICollateralManagement collateralManagement;
        IFlyoverConfigurations configurations;
        mapping(bytes32 => Quotes.PegOutQuote) quotes;
        mapping(bytes32 => EscrowedPegOutState) state;
        mapping(uint256 => bytes32) idByNonce;
        uint256 requestCount;
    }

    string public constant VERSION = "0.1.0-poc";
    /// @notice Basis-point denominator for `percentageFee` (frozen on {IPegOutEscrow})
    uint256 public constant FEE_PERCENTAGE_DENOMINATOR = 10_000;

    // ERC-7201: keccak256(abi.encode(uint256(keccak256("rsk.flyover.PegOutEscrow")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _PEGOUT_ESCROW_STORAGE =
        0xb99c8d82bac3ff4ec6a3e7ff5aa17dda321aa2a152ae7dc22fe007bc5dcb3000;

    event PegOutContractSet(address indexed oldAddress, address indexed newAddress);
    event FlyoverConfigurationsSet(address indexed oldAddress, address indexed newAddress);

    error FlyoverConfigurationsNotSet();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // solhint-disable-next-line comprehensive-interface
    receive() external payable {
        revert Flyover.PaymentNotAllowed();
    }

    /// @notice Initializes the escrow
    // solhint-disable-next-line comprehensive-interface
    function initialize(
        address defaultAdmin,
        uint48 initialDelay,
        IPauseRegistry pauseRegistry_,
        address pegOutContract_,
        address collateralManagement_,
        address configurations_
    ) external initializer {
        if (address(pauseRegistry_).code.length == 0) revert Flyover.NoContract(address(pauseRegistry_));
        if (pegOutContract_.code.length == 0) revert Flyover.NoContract(pegOutContract_);
        if (collateralManagement_.code.length == 0) revert Flyover.NoContract(collateralManagement_);
        if (configurations_.code.length == 0) revert Flyover.NoContract(configurations_);

        __AccessControlDefaultAdminRules_init(initialDelay, defaultAdmin);
        __EmergencyPause_init(pauseRegistry_);

        PegOutEscrowStorage storage $ = _getStorage();
        $.pegOutContract = IPegOut(pegOutContract_);
        $.collateralManagement = ICollateralManagement(collateralManagement_);
        $.configurations = IFlyoverConfigurations(payable(configurations_));
    }

    // solhint-disable-next-line comprehensive-interface
    function setPegOutContract(address pegOutContract_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (pegOutContract_.code.length == 0) revert Flyover.NoContract(pegOutContract_);
        PegOutEscrowStorage storage $ = _getStorage();
        emit PegOutContractSet(address($.pegOutContract), pegOutContract_);
        $.pegOutContract = IPegOut(pegOutContract_);
    }

    // solhint-disable-next-line comprehensive-interface
    function setCollateralManagement(address collateralManagement_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (collateralManagement_.code.length == 0) revert Flyover.NoContract(collateralManagement_);
        PegOutEscrowStorage storage $ = _getStorage();
        emit CollateralManagementSet(address($.collateralManagement), collateralManagement_);
        $.collateralManagement = ICollateralManagement(collateralManagement_);
    }

    // solhint-disable-next-line comprehensive-interface
    function setFlyoverConfigurations(address configurations_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (configurations_.code.length == 0) revert Flyover.NoContract(configurations_);
        PegOutEscrowStorage storage $ = _getStorage();
        emit FlyoverConfigurationsSet(address($.configurations), configurations_);
        $.configurations = IFlyoverConfigurations(payable(configurations_));
    }

    /// @inheritdoc IPegOutEscrow
    function requestPegOut(
        bytes calldata destinationAddress,
        address refundAddress
    ) external payable override nonReentrant whenNotSoftPaused returns (bytes32 requestHash) {
        if (destinationAddress.length == 0) revert InvalidDestination();
        if (refundAddress == address(0)) revert InvalidRefundAddress();

        PegOutEscrowStorage storage $ = _getStorage();
        if (address($.pegOutContract) == address(0)) revert PegOutContractNotSet();
        if (address($.configurations) == address(0)) revert FlyoverConfigurationsNotSet();

        IFlyoverConfigurations.PegOutConfiguration memory cfg = $.configurations.getPegOutConfiguration();
        (uint256 amount, uint256 callFee, uint256 change) = _splitValue($, msg.value, cfg);
        if (amount < cfg.minAmount || amount > cfg.maxAmount) {
            revert NotServiceable(amount, cfg.minAmount, cfg.maxAmount);
        }

        uint256 nonce = ++$.requestCount;
        requestHash = _computeRequestHash(nonce, refundAddress, destinationAddress, amount, callFee);

        $.state[requestHash] = EscrowedPegOutState.REQUESTED;
        $.idByNonce[nonce] = requestHash;

        uint256 confirmations = $.configurations.getRequiredPegOutBtcConfirmations(amount);
        $.quotes[requestHash] =
            _buildQuote($, cfg, refundAddress, destinationAddress, amount, callFee, nonce, confirmations);

        emit PegOutRequested(requestHash, refundAddress, amount, destinationAddress);

        if (change > 0) {
            emit PegOutChangePaid(requestHash, refundAddress, change);
            _payout(refundAddress, change);
        }
    }

    function _computeRequestHash(
        uint256 nonce,
        address refundTo,
        bytes calldata destinationAddress,
        uint256 amount,
        uint256 callFee
    ) private view returns (bytes32) {
        return keccak256(
            abi.encode(
                block.chainid,
                address(this),
                nonce,
                msg.sender,
                refundTo,
                keccak256(destinationAddress),
                amount,
                callFee,
                block.timestamp
            )
        );
    }

    function _buildQuote(
        PegOutEscrowStorage storage $,
        IFlyoverConfigurations.PegOutConfiguration memory cfg,
        address refundTo,
        bytes calldata destinationAddress,
        uint256 amount,
        uint256 callFee,
        uint256 nonce,
        uint256 confirmations
    ) private view returns (Quotes.PegOutQuote memory quote) {
        uint256 latestClaim = block.timestamp + cfg.claimWindow;
        uint256 latestClaimBlock = block.number + cfg.claimWindowBlocks;
        quote = Quotes.PegOutQuote({
            chainId: block.chainid,
            callFee: callFee,
            penaltyFee: cfg.penaltyFee,
            value: amount,
            gasFee: cfg.gasFee,
            lbcAddress: address($.pegOutContract),
            lpRskAddress: address(0),
            rskRefundAddress: refundTo,
            nonce: int64(uint64(nonce)),
            agreementTimestamp: uint32(block.timestamp),
            depositDateLimit: uint32(latestClaim),
            transferTime: uint32(cfg.callTime),
            expireDate: uint32(latestClaim + cfg.expireTime),
            expireBlock: uint32(latestClaimBlock + cfg.expireBlocks),
            depositConfirmations: uint16(cfg.depositConfirmations),
            transferConfirmations: uint16(confirmations),
            depositAddress: destinationAddress,
            btcRefundAddress: "",
            lpBtcAddress: ""
        });
    }

    /// @inheritdoc IPegOutEscrow
    function cancelPegOut(bytes32 requestHash) external override nonReentrant whenNotSoftPaused {
        PegOutEscrowStorage storage $ = _getStorage();
        _requireRequested($, requestHash);
        Quotes.PegOutQuote memory q = $.quotes[requestHash];
        if (msg.sender != q.rskRefundAddress) {
            revert Flyover.InvalidSender(q.rskRefundAddress, msg.sender);
        }

        uint256 payout = q.value + q.callFee + q.gasFee;
        _terminate($, requestHash, EscrowedPegOutState.CANCELLED);
        emit PegOutCancelled(requestHash);
        _payout(q.rskRefundAddress, payout);
    }

    /// @inheritdoc IPegOutEscrow
    function claimPegOut(bytes32 requestHash, bytes calldata signature)
        external
        override
        nonReentrant
        whenNotSoftPaused
    {
        PegOutEscrowStorage storage $ = _getStorage();
        _requireRequested($, requestHash);

        Quotes.PegOutQuote storage q = $.quotes[requestHash];
        if (block.timestamp > q.depositDateLimit) {
            revert ClaimWindowClosed(q.depositDateLimit);
        }
        if (address($.collateralManagement) == address(0)) revert CollateralManagementNotSet();
        if (!$.collateralManagement.isCollateralSufficient(Flyover.ProviderType.PegOut, msg.sender)) {
            revert Flyover.ProviderNotRegistered(msg.sender);
        }

        q.lpRskAddress = msg.sender;
        $.state[requestHash] = EscrowedPegOutState.CLAIMED;

        uint256 valueToSend = q.value + q.callFee + q.gasFee;
        emit PegOutClaimed(msg.sender, requestHash);

        $.pegOutContract.registerClaimedPegOut{value: valueToSend}(requestHash, signature);
    }

    /// @inheritdoc IPegOutEscrow
    function refundOnNoClaim(bytes32 requestHash) external override nonReentrant whenNotSoftPaused {
        PegOutEscrowStorage storage $ = _getStorage();
        _requireRequested($, requestHash);
        Quotes.PegOutQuote memory q = $.quotes[requestHash];
        if (block.timestamp <= q.depositDateLimit) {
            revert ClaimWindowOpen(q.depositDateLimit);
        }

        uint256 payout = q.value + q.callFee + q.gasFee;
        _terminate($, requestHash, EscrowedPegOutState.REFUNDED);
        emit PegOutRefundedOnNoClaim(requestHash, q.rskRefundAddress, payout);

        // If globalSlash reverts (e.g. stub / no eligible LPs), user still gets the refund.
        if (address($.collateralManagement) == address(0)) revert CollateralManagementNotSet();
        try $.collateralManagement.globalSlash(q.penaltyFee) {}
        catch {
            emit GlobalSlashSkipped(requestHash);
        }

        _payout(q.rskRefundAddress, payout);
    }

    /// @inheritdoc IPegOutEscrow
    function onSettlement(bytes32 requestHash, EscrowedPegOutState finalState) external override {
        PegOutEscrowStorage storage $ = _getStorage();
        if (msg.sender != address($.pegOutContract)) {
            revert OnlyPegOutContract(msg.sender);
        }
        if ($.state[requestHash] != EscrowedPegOutState.CLAIMED) {
            revert InvalidState(requestHash, EscrowedPegOutState.CLAIMED, $.state[requestHash]);
        }
        if (finalState != EscrowedPegOutState.FULFILLED && finalState != EscrowedPegOutState.REFUNDED) {
            revert InvalidState(requestHash, EscrowedPegOutState.FULFILLED, finalState);
        }
        _terminate($, requestHash, finalState);
    }

    /// @inheritdoc IPegOutEscrow
    function getPegOutState(bytes32 requestHash) external view override returns (EscrowedPegOutState) {
        return _getStorage().state[requestHash];
    }

    /// @inheritdoc IPegOutEscrow
    function getPegOutQuote(bytes32 requestHash) external view override returns (Quotes.PegOutQuote memory) {
        PegOutEscrowStorage storage $ = _getStorage();
        if ($.state[requestHash] == EscrowedPegOutState.NONE) {
            revert Flyover.QuoteNotFound(requestHash);
        }
        return $.quotes[requestHash];
    }

    /// @inheritdoc IPegOutEscrow
    function totalRequests() external view override returns (uint256) {
        return _getStorage().requestCount;
    }

    /// @inheritdoc IPegOutEscrow
    function requestIdAt(uint256 nonce) external view override returns (bytes32) {
        return _getStorage().idByNonce[nonce];
    }

    // solhint-disable-next-line comprehensive-interface
    function getPegOutContract() external view returns (address) {
        return address(_getStorage().pegOutContract);
    }

    // solhint-disable-next-line comprehensive-interface
    function getFlyoverConfigurations() external view returns (address) {
        return address(_getStorage().configurations);
    }

    /// @dev Inverse fee split, then apply dust-change return against PegOutContract.dustThreshold.
    /// Residual at or above the threshold is returned as `change`; smaller residual is folded
    /// into `callFee` so cancel / claim / no-claim payouts still drain the escrow.
    /// `gasFee` is taken from config so the LP is reimbursed for BTC tx cost on settlement.
    function _splitValue(
        PegOutEscrowStorage storage $,
        uint256 value,
        IFlyoverConfigurations.PegOutConfiguration memory cfg
    ) private view returns (uint256 amount, uint256 callFee, uint256 change) {
        uint256 gasFee = cfg.gasFee;
        if (value <= cfg.fixedFee + gasFee) {
            revert Flyover.InsufficientAmount(value, cfg.fixedFee + gasFee + 1);
        }
        amount = ((value - cfg.fixedFee - gasFee) * FEE_PERCENTAGE_DENOMINATOR)
            / (FEE_PERCENTAGE_DENOMINATOR + cfg.percentageFee);
        amount -= amount % Quotes.SAT_TO_WEI_CONVERSION;
        callFee = $.configurations.calculatePegOutFee(amount);
        uint256 required = amount + callFee + gasFee;
        if (value < required) {
            revert Flyover.InsufficientAmount(value, required);
        }
        change = value - required;
        uint256 dust = _dustThreshold(address($.pegOutContract));
        if (dust > change) {
            callFee += change;
            change = 0;
        }
    }

    /// @dev PegOutContract exposes `dustThreshold` as a public getter; keep the dependency
    /// narrow so PegOutEscrow does not import the concrete settlement contract.
    function _dustThreshold(address pegOutContract) private view returns (uint256) {
        return IDustThreshold(pegOutContract).dustThreshold();
    }

    function _requireRequested(PegOutEscrowStorage storage $, bytes32 requestHash) private view {
        EscrowedPegOutState actual = $.state[requestHash];
        if (actual != EscrowedPegOutState.REQUESTED) {
            revert InvalidState(requestHash, EscrowedPegOutState.REQUESTED, actual);
        }
    }

    function _terminate(
        PegOutEscrowStorage storage $,
        bytes32 requestHash,
        EscrowedPegOutState finalState
    ) private {
        $.state[requestHash] = finalState;
        delete $.quotes[requestHash];
    }

    function _payout(address to, uint256 amount) private {
        (bool sent, bytes memory reason) = to.call{value: amount}("");
        if (!sent) {
            revert Flyover.PaymentFailed(to, amount, reason);
        }
    }

    function _getStorage() private pure returns (PegOutEscrowStorage storage $) {
        bytes32 slot = _PEGOUT_ESCROW_STORAGE;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := slot
        }
    }
}
