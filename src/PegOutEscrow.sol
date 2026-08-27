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
import {SignatureValidator} from "./libraries/SignatureValidator.sol";

/// @title PegOutEscrow
/// @notice Commit-first peg-out escrow. User deposits RBTC first; LPs claim and settle via
/// PegOutContract. Fee / deadline parameters come from {IFlyoverConfigurations}.
/// @author Rootstock Labs
contract PegOutEscrow is
    AccessControlDefaultAdminRulesUpgradeable,
    EmergencyPause,
    ReentrancyGuard,
    IPegOutEscrow
{
    /// @custom:storage-location erc7201:rsk.flyover.PegOutEscrow
    struct PegOutEscrowStorage {
        /// Settlement contract (claim forwards funds here; also supplies dustThreshold).
        IPegOut pegOutContract;
        /// Collateral registry used by claim / no-claim global slash.
        ICollateralManagement collateralManagement;
        /// Active peg-out fee, bounds, deadlines, and confirmation tiers.
        IFlyoverConfigurations configurations;
        /// Quote-shaped terms snapshotted at request (deleted on cancel / terminal states).
        mapping(bytes32 => Quotes.PegOutQuote) quotes;
        /// Lifecycle per requestHash (`NONE` if never requested).
        mapping(bytes32 => EscrowedPegOutState) state;
        /// requestHash for each 1-based nonce; LPS rebuild after missed events.
        mapping(uint256 => bytes32) requestHashByNonce;
        /// How many requests have been minted; next request uses `++requestCount`.
        uint256 requestCount;
        /// Per-LP claim-fail count `n` (freeze length uses `RESTRICTION_BASE ** n`).
        mapping(address => uint256) claimFailCount;
        /// Per-LP claim gate: `0` ⇒ not frozen; claim reverts while `now < restrictedUntil`.
        mapping(address => uint256) restrictedUntil;
    }

    string public constant VERSION = "1.0.0";

    /// @notice Basis-point denominator for `percentageFee` (frozen on {IPegOutEscrow})
    uint256 public constant FEE_PERCENTAGE_DENOMINATOR = 10_000;

    /// @notice Unit for claim-fail freeze duration (`(BASE ** n) * UNIT`)
    uint256 public constant RESTRICTION_UNIT = 1 days;

    /// @notice Base for claim-fail freeze duration (`(BASE ** n) * UNIT`)
    uint256 public constant RESTRICTION_BASE = 2;

    // ERC-7201: keccak256(abi.encode(uint256(keccak256("rsk.flyover.PegOutEscrow")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _PEGOUT_ESCROW_STORAGE =
        0xb99c8d82bac3ff4ec6a3e7ff5aa17dda321aa2a152ae7dc22fe007bc5dcb3000;

    event PegOutContractSet(address indexed oldAddress, address indexed newAddress);
    event FlyoverConfigurationsSet(address indexed oldAddress, address indexed newAddress);

    /// @notice Excess above `amount + callFee + gasFee` returned when at/above dust (not on frozen ABI).
    event EscrowPegOutChangePaid(bytes32 indexed requestHash, address indexed refundAddress, uint256 indexed change);

    error FlyoverConfigurationsNotSet();
    error PegOutPathNotImplemented();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // solhint-disable-next-line comprehensive-interface
    receive() external payable {
        revert Flyover.PaymentNotAllowed();
    }

    /// @notice Initializes the escrow and wires dependencies.
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
        if (refundAddress == address(0)) revert Flyover.InvalidAddress(refundAddress);

        PegOutEscrowStorage storage $ = _getStorage();
        if (address($.pegOutContract) == address(0)) revert PegOutContractNotSet();
        if (address($.configurations) == address(0)) revert FlyoverConfigurationsNotSet();

        IFlyoverConfigurations.PegOutConfiguration memory cfg = $.configurations.getPegOutConfiguration();
        (uint256 amount, uint256 callFee, uint256 gasFee, uint256 changeRefund) =
            _splitValue($, msg.value, cfg);
        if (amount < cfg.minAmount || amount > cfg.maxAmount) {
            revert NotServiceable(amount, cfg.minAmount, cfg.maxAmount);
        }

        uint256 nonce = ++$.requestCount;
        uint256 confirmations = $.configurations.getRequiredPegOutBtcConfirmations(amount);
        requestHash = _registerRequestedPegOut(
            $,
            cfg,
            refundAddress,
            destinationAddress,
            amount,
            callFee,
            gasFee,
            nonce,
            confirmations
        );

        if (changeRefund > 0) {
            emit EscrowPegOutChangePaid(requestHash, refundAddress, changeRefund);
            _payout(refundAddress, changeRefund);
        }
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
        if (!$.collateralManagement.isRegistered(Flyover.ProviderType.PegOut, msg.sender)) {
            revert Flyover.ProviderNotRegistered(msg.sender);
        }
        if (!$.collateralManagement.isCollateralSufficient(Flyover.ProviderType.PegOut, msg.sender)) {
            revert IPegOut.InsufficientCollateral(
                $.collateralManagement.getPegOutCollateral(msg.sender)
            );
        }
        uint256 until = $.restrictedUntil[msg.sender];
        if (block.timestamp < until) {
            revert LpRestricted(msg.sender, until);
        }

        q.lpRskAddress = msg.sender;
        Quotes.PegOutQuote memory signedQuote = q;
        bytes32 eip712Hash = $.pegOutContract.hashPegOutQuoteEIP712(signedQuote);
        if (!SignatureValidator.verify(msg.sender, eip712Hash, signature)) {
            revert SignatureValidator.IncorrectSignature(msg.sender, eip712Hash, signature);
        }

        // Set CLAIMED before depositPegOut so PegOut's escrow-state check holds.
        $.state[requestHash] = EscrowedPegOutState.CLAIMED;

        uint256 valueToSend = q.value + q.callFee + q.gasFee;
        emit PegOutClaimed(msg.sender, requestHash);

        $.pegOutContract.depositPegOut{value: valueToSend}(signedQuote, signature);
    }

    /// @inheritdoc IPegOutEscrow
    function refundOnNoClaim(bytes32 requestHash) external override nonReentrant whenNotSoftPaused {
        PegOutEscrowStorage storage $ = _getStorage();
        _requireRequested($, requestHash);
        Quotes.PegOutQuote memory q = $.quotes[requestHash];
        // solhint-disable-next-line gas-strict-inequalities
        if (block.timestamp <= q.depositDateLimit) {
            revert ClaimWindowOpen(q.depositDateLimit);
        }
        if (address($.collateralManagement) == address(0)) revert CollateralManagementNotSet();

        uint256 payout = q.value + q.callFee + q.gasFee;
        _terminate($, requestHash, EscrowedPegOutState.REFUNDED);
        emit PegOutRefundedOnNoClaim(requestHash, q.rskRefundAddress, payout);

        // If globalSlash reverts (stub / missing role / no eligible LPs), user still refunded.
        // solhint-disable-next-line no-empty-blocks
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
    function onClaimFail(address lp) external override {
        PegOutEscrowStorage storage $ = _getStorage();
        if (msg.sender != address($.pegOutContract)) {
            revert OnlyPegOutContract(msg.sender);
        }
        uint256 n = ++$.claimFailCount[lp];
        $.restrictedUntil[lp] = block.timestamp + ((RESTRICTION_BASE ** n) * RESTRICTION_UNIT);
    }

    /// @inheritdoc IPegOutEscrow
    function revoke(address lp) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _getStorage().restrictedUntil[lp] = type(uint256).max;
    }

    /// @inheritdoc IPegOutEscrow
    function unrevoke(address lp) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _getStorage().restrictedUntil[lp] = 0;
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
        return _getStorage().requestHashByNonce[nonce];
    }

    /// @inheritdoc IPegOutEscrow
    function claimFailCount(address lp) external view override returns (uint256) {
        return _getStorage().claimFailCount[lp];
    }

    /// @inheritdoc IPegOutEscrow
    function restrictedUntil(address lp) external view override returns (uint256) {
        return _getStorage().restrictedUntil[lp];
    }

    // solhint-disable-next-line comprehensive-interface
    function getPegOutContract() external view returns (address) {
        return address(_getStorage().pegOutContract);
    }

    // solhint-disable-next-line comprehensive-interface
    function getFlyoverConfigurations() external view returns (address) {
        return address(_getStorage().configurations);
    }

    function _registerRequestedPegOut(
        PegOutEscrowStorage storage $,
        IFlyoverConfigurations.PegOutConfiguration memory cfg,
        address refundAddress,
        bytes calldata destinationAddress,
        uint256 amount,
        uint256 callFee,
        uint256 gasFee,
        uint256 nonce,
        uint256 confirmations
    ) private returns (bytes32 requestHash) {
        Quotes.PegOutQuote memory quote = _buildQuote(
            $,
            cfg,
            refundAddress,
            destinationAddress,
            amount,
            callFee,
            gasFee,
            nonce,
            confirmations
        );

        requestHash = $.pegOutContract.hashPegOutQuote(quote);

        $.state[requestHash] = EscrowedPegOutState.REQUESTED;
        $.requestHashByNonce[nonce] = requestHash;
        $.quotes[requestHash] = quote;

        emit PegOutRequested(requestHash, refundAddress, amount, destinationAddress);
    }

    function _terminate(
        PegOutEscrowStorage storage $,
        bytes32 requestHash,
        EscrowedPegOutState finalState
    ) private {
        $.state[requestHash] = finalState;
        delete $.quotes[requestHash];
    }

    // slither-disable-next-line arbitrary-send-eth,low-level-calls
    function _payout(address to, uint256 amount) private {
        address target = to;
        uint256 value = amount;
        uint256 gasLimit = gasleft();
        bytes memory data = "";
        bool success;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            success := call(gasLimit, target, value, add(data, 0x20), mload(data), 0, 0)
        }
        if (!success) {
            revert Flyover.PaymentFailed(to, amount, hex"");
        }
    }

    function _buildQuote(
        PegOutEscrowStorage storage $,
        IFlyoverConfigurations.PegOutConfiguration memory cfg,
        address refundTo,
        bytes calldata destinationAddress,
        uint256 amount,
        uint256 callFee,
        uint256 gasFee,
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
            gasFee: gasFee,
            lbcAddress: address($.pegOutContract),
            lpRskAddress: address(0),
            rskRefundAddress: refundTo,
            nonce: int64(uint64(nonce)),
            agreementTimestamp: uint32(block.timestamp),
            depositDateLimit: uint32(latestClaim),
            transferTime: uint32(cfg.callTime),
            expireDate: uint32(latestClaim + cfg.expireTime),
            expireBlock: uint32(latestClaimBlock + cfg.expireBlocks),
            // TODO: snapshot from config if frozen PegOutConfiguration regains depositConfirmations
            depositConfirmations: 0,
            transferConfirmations: uint16(confirmations),
            depositAddress: destinationAddress,
            btcRefundAddress: "",
            lpBtcAddress: ""
        });
    }

    /// @dev Derives principal `amount` and `callFee` from `msg.value` after reserving
    /// snapshotted `gasFee` (= config `maxMinerFee`), floors `amount` to a satoshi,
    /// then applies dust-change: residual ≥ PegOutContract.dustThreshold is returned as
    /// `changeRefund`; smaller residual is folded into `callFee` so escrow stays fully attributed.
    /// TODO: revisit fee economics — whether `quote.gasFee` should stay a full `maxMinerFee`
    /// snapshot, a smaller reserved miner buffer, or a different split vs `callFee` / principal.
    function _splitValue(
        PegOutEscrowStorage storage $,
        uint256 value,
        IFlyoverConfigurations.PegOutConfiguration memory cfg
    ) private view returns (uint256 amount, uint256 callFee, uint256 gasFee, uint256 changeRefund) {
        gasFee = cfg.maxMinerFee;
        // solhint-disable-next-line gas-strict-inequalities
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
        changeRefund = value - required;
        uint256 dust = $.pegOutContract.dustThreshold();
        // Match PegOutContract.depositPegOut: fold when dust > change (refund when change >= dust).
        // solhint-disable-next-line gas-strict-inequalities
        if (dust > changeRefund) {
            callFee += changeRefund;
            changeRefund = 0;
        }
    }

    function _requireRequested(PegOutEscrowStorage storage $, bytes32 requestHash) private view {
        EscrowedPegOutState actual = $.state[requestHash];
        if (actual != EscrowedPegOutState.REQUESTED) {
            revert InvalidState(requestHash, EscrowedPegOutState.REQUESTED, actual);
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
