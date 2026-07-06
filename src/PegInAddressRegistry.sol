// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {BtcUtils} from "@rsksmart/btc-transaction-solidity-helper/contracts/BtcUtils.sol";
import {IBridge} from "./interfaces/IBridge.sol";
import {IPegInAddressRegistry} from "./interfaces/IPegInAddressRegistry.sol";
import {Flyover} from "./libraries/Flyover.sol";
import {PegInDerivation} from "./libraries/PegInDerivation.sol";

/// @title PegInAddressRegistry
/// @notice Upgradeable registry that derives a static BTC deposit address from an RSK
/// address against the current powpeg, and lets any caller register that RSK address by
/// presenting an SPV proof of a BTC deposit to the derived address (no signature required).
/// @dev The derivation is the bridge-compatible PLAIN P2SH built by the shared
/// {PegInDerivation} library — the SAME construction `PegInContract` settles against. The
/// derivation value mixes `keccak256(DERIVATION_DOMAIN, rskAddr)` with the protocol placeholder
/// BTC addresses and the wired PegInContract (lbcAddress); see {PegInDerivation} for the proof.
/// @author Rootstock Labs
contract PegInAddressRegistry is
    AccessControlDefaultAdminRulesUpgradeable,
    ReentrancyGuard,
    IPegInAddressRegistry
{
    /// @notice The version of the contract
    string public constant VERSION = "1.0.0";

    /// @notice Versioned scheme tag mixed into every derivation. Bumping it deterministically
    /// changes every derived address, the same path the system handles for a federation change.
    /// @dev Mirrors {PegInDerivation.DERIVATION_DOMAIN} (the single source of truth).
    bytes public constant DERIVATION_DOMAIN = "FLYOVER_PEGIN_V1";

    /// @notice The encoding of the addresses returned by the derivation getters. The derived
    /// address is a base58check-encoded P2SH address, matching the construction in PegInContract.
    Encoding public constant ADDRESS_ENCODING = Encoding.BASE58;

    /// @dev Minimum BTC confirmations required for a deposit proof to gate a registration.
    /// `getBtcTransactionConfirmations` returns the confirmation count (>= 0) on success, or a
    /// negative error code when the tx/block is unknown to the Bridge. PoC uses 1.
    int256 private constant _MIN_CONFIRMATIONS = 1;

    /// @custom:storage-location erc7201:rsk.flyover.PegInAddressRegistry
    struct PegInAddressRegistryStorage {
        IBridge bridge;
        bool mainnet;
        uint256 count;
        bytes32 registrationRoot;
        mapping(address => uint256) registrationBlock;
        // APPENDED (never reorder the fields above): the PegInContract (lbcAddress) that calls the
        // native fast bridge. It is mixed into the deposit-address derivation, so the registry and
        // the settlement path agree on the address the bridge re-derives. Wired post-deploy.
        address pegInContract;
    }

    // ERC-7201: keccak256(abi.encode(uint256(keccak256("rsk.flyover.PegInAddressRegistry")) - 1)) &
    // ~bytes32(uint256(0xff))
    bytes32 private constant _PEGIN_ADDRESS_REGISTRY_STORAGE =
        0x0704e3acad2c0308b9997bc861208a21efddaa710005747040bdddc7b9400f00;

    /// @notice Raised when an address that is already registered is registered again
    error AlreadyRegistered(address addr);
    /// @notice Raised when no output of the supplied BTC tx pays the address derived for `addr`
    error DepositAddressMismatch(address addr);
    /// @notice Raised when the bridge does not confirm a valid deposit to the derived address
    error InvalidDepositProof(address addr, int256 bridgeResult);
    /// @notice Raised when an address derivation is attempted before the PegInContract is wired.
    /// The PegInContract (lbcAddress) is mixed into the derivation, so it MUST be set first.
    error PegInContractNotSet();

    /// @notice Emitted when the PegInContract (lbcAddress) mixed into the derivation is set.
    event PegInContractSet(address indexed oldPegInContract, address indexed newPegInContract);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice This contract does not accept value
    // solhint-disable-next-line comprehensive-interface
    receive() external payable {
        revert Flyover.PaymentNotAllowed();
    }

    /// @notice Initializes the contract
    /// @param defaultAdmin The default admin of the contract
    /// @param initialDelay The initial delay for changes in the default admin role
    /// @param bridge The address of the Rootstock bridge
    /// @param mainnet Whether the derived addresses target mainnet or testnet
    // solhint-disable-next-line comprehensive-interface
    function initialize(
        address defaultAdmin,
        uint48 initialDelay,
        address bridge,
        bool mainnet
    ) external initializer {
        // NOTE: the bridge is the Rootstock precompile (0x...1000006), which is a
        // native contract with no EVM bytecode, so a code.length guard is wrong here
        // (it always reads 0). The original PegInContract likewise does not guard the
        // bridge. We only require a non-zero address.
        if (bridge == address(0)) revert Flyover.NoContract(bridge);
        __AccessControlDefaultAdminRules_init(initialDelay, defaultAdmin);
        PegInAddressRegistryStorage storage $ = _getStorage();
        $.bridge = IBridge(payable(bridge));
        $.mainnet = mainnet;
    }

    /// @inheritdoc IPegInAddressRegistry
    function registerAddress(
        address addr,
        bytes calldata btcTxSerialized,
        bytes32 btcBlockHash,
        uint256 merkleBranchPath,
        bytes32[] calldata merkleBranchHashes
    ) external nonReentrant override {
        PegInAddressRegistryStorage storage $ = _getStorage();
        if ($.registrationBlock[addr] != 0) {
            revert AlreadyRegistered(addr);
        }

        // READ-ONLY deposit-gating: this VALIDATES — without consuming — that a confirmed BTC tx
        // pays the address derived for `addr`. It is permissionless (msg.sender is never checked
        // against addr) and changes no state until every check passes.
        //
        // 1. Parse the tx outputs in-contract and require at least one pays the derived P2SH.
        // 2. Read confirmations for the tx from the Bridge VIEW `getBtcTransactionConfirmations`.
        //
        // We deliberately do NOT call the Bridge's `registerFastBridgeBtcTransaction`: that is the
        // one-shot peg-in SETTLEMENT owned by `PegInContract.resolvePegIn`. Calling it here would
        // consume the peg-in (breaking the LP's claim) and land funds in this registry. The
        // registry only proves a deposit exists; the actual settlement stays in resolvePegIn.

        // (1) Output must pay the address derived for `addr` against the active powpeg.
        bytes memory expectedScriptPubkey = _p2shScriptPubkey(addr);
        BtcUtils.TxRawOutput[] memory outputs = BtcUtils.getOutputs(btcTxSerialized);
        bool paysDerived = false;
        for (uint256 i = 0; i < outputs.length; ++i) {
            if (keccak256(outputs[i].pkScript) == keccak256(expectedScriptPubkey)) {
                paysDerived = true;
                break;
            }
        }
        if (!paysDerived) {
            revert DepositAddressMismatch(addr);
        }

        // (2) The tx must be confirmed on the BTC chain per the Bridge (read-only).
        // txHash is the canonical BTC txid: byte-reversed double-SHA256 of the serialized tx.
        bytes32 btcTxHash = BtcUtils.hashBtcTx(btcTxSerialized);
        int256 confirmations = $.bridge.getBtcTransactionConfirmations(
            btcTxHash,
            btcBlockHash,
            merkleBranchPath,
            merkleBranchHashes
        );
        if (confirmations < _MIN_CONFIRMATIONS) {
            revert InvalidDepositProof(addr, confirmations);
        }

        $.registrationBlock[addr] = block.number;
        $.count += 1;
        _updateRoot(addr);
        emit AddressRegistered(addr, $.registrationRoot);
    }

    /// @inheritdoc IPegInAddressRegistry
    function getPegInAddress(address addr) external view override returns (bytes memory, Encoding) {
        return (_deriveAddress(addr), ADDRESS_ENCODING);
    }

    /// @inheritdoc IPegInAddressRegistry
    function getPegInAddresses(address[] calldata addrs)
        external
        view
        override
        returns (bytes[] memory derivationAddresses, Encoding encoding)
    {
        derivationAddresses = new bytes[](addrs.length);
        for (uint256 i = 0; i < addrs.length; ++i) {
            derivationAddresses[i] = _deriveAddress(addrs[i]);
        }
        encoding = ADDRESS_ENCODING;
    }

    /// @inheritdoc IPegInAddressRegistry
    function getRegistrationRoot() external view override returns (bytes32) {
        return _getStorage().registrationRoot;
    }

    /// @inheritdoc IPegInAddressRegistry
    function isRegistered(address addr) external view override returns (bool) {
        return _getStorage().registrationBlock[addr] != 0;
    }

    /// @inheritdoc IPegInAddressRegistry
    function getRegistrationBlock(address addr) external view override returns (uint256) {
        return _getStorage().registrationBlock[addr];
    }

    /// @inheritdoc IPegInAddressRegistry
    function getRegistrationCount() external view override returns (uint256) {
        return _getStorage().count;
    }

    /// @notice Returns the bridge the registry derives against
    function getBridge() external view returns (IBridge) {
        return _getStorage().bridge;
    }

    /// @notice Sets the PegInContract (lbcAddress) mixed into the deposit-address derivation.
    /// @dev MUST equal `address(PegInContract)` — the contract that calls the native fast bridge's
    /// `registerFastBridgeBtcTransaction` — so the address the registry shows is the address the
    /// bridge re-derives at settlement. Admin-only, append-only wiring; settable post-deploy.
    /// @param pegInContract The PegInContract address
    // solhint-disable-next-line comprehensive-interface
    function setPegInContract(address pegInContract) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        if (pegInContract == address(0)) revert Flyover.NoContract(pegInContract);
        PegInAddressRegistryStorage storage $ = _getStorage();
        emit PegInContractSet($.pegInContract, pegInContract);
        $.pegInContract = pegInContract;
    }

    /// @notice Returns the PegInContract (lbcAddress) mixed into the derivation (0 if unset).
    // solhint-disable-next-line comprehensive-interface
    function getPegInContract() external view returns (address) {
        return _getStorage().pegInContract;
    }

    /// @notice Updates the running-hash accumulator over the registered set
    /// @dev registrationRoot = keccak256(abi.encodePacked(registrationRoot, rskAddr)), order-dependent
    /// @param rskAddr The RSK address being folded into the root
    function _updateRoot(address rskAddr) private {
        PegInAddressRegistryStorage storage $ = _getStorage();
        $.registrationRoot = keccak256(abi.encodePacked($.registrationRoot, rskAddr));
    }

    /// @notice Derives the BTC deposit address for an RSK address against the current powpeg
    /// @dev Builds the bridge-compatible PLAIN P2SH via the shared {PegInDerivation} library — the
    /// SAME construction `PegInContract` settles against. Reads the active powpeg redeem script live
    /// from the Bridge on every call. Reverts {PegInContractNotSet} until the lbcAddress is wired.
    /// @param addr The RSK address
    /// @return The base58check payload of the derived BTC deposit address
    function _deriveAddress(address addr) private view returns (bytes memory) {
        PegInAddressRegistryStorage storage $ = _getStorage();
        address pegInContract = $.pegInContract;
        if (pegInContract == address(0)) revert PegInContractNotSet();
        return PegInDerivation.depositAddressPayload(
            addr,
            pegInContract,
            $.bridge.getActivePowpegRedeemScript(),
            $.mainnet
        );
    }

    /// @notice Builds the on-chain P2SH output script that a BTC deposit to `addr` must carry:
    /// OP_HASH160 <hash160(flyoverRedeemScript)> OP_EQUAL. This is the raw pkScript form a parsed
    /// tx output exposes, so the deposit-gating compares it directly against the outputs. Uses the
    /// shared {PegInDerivation} library so it matches the bridge-settled PLAIN P2SH exactly.
    /// @param addr The RSK address
    /// @return The 25-byte P2SH scriptPubkey for `addr`
    function _p2shScriptPubkey(address addr) private view returns (bytes memory) {
        PegInAddressRegistryStorage storage $ = _getStorage();
        address pegInContract = $.pegInContract;
        if (pegInContract == address(0)) revert PegInContractNotSet();
        return PegInDerivation.p2shScriptPubkey(
            addr,
            pegInContract,
            $.bridge.getActivePowpegRedeemScript()
        );
    }

    function _getStorage() private pure returns (PegInAddressRegistryStorage storage $) {
        assembly {
            $.slot := _PEGIN_ADDRESS_REGISTRY_STORAGE
        }
    }
}
