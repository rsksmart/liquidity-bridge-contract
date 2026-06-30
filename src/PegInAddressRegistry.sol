// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {BtcUtils} from "@rsksmart/btc-transaction-solidity-helper/contracts/BtcUtils.sol";
import {OpCodes} from "@rsksmart/btc-transaction-solidity-helper/contracts/OpCodes.sol";
import {IBridge} from "./interfaces/IBridge.sol";
import {IPegInAddressRegistry} from "./interfaces/IPegInAddressRegistry.sol";
import {Flyover} from "./libraries/Flyover.sol";

/// @title PegInAddressRegistry
/// @notice Upgradeable registry that derives a static BTC deposit address from an RSK
/// address against the current powpeg, and lets any caller register that RSK address by
/// presenting an SPV proof of a BTC deposit to the derived address (no signature required).
/// @dev The derivation mirrors `PegInContract.validatePegInDepositAddress`, but keys the
/// derivation value on the RSK address plus a versioned domain tag instead of the quote hash.
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
    bytes public constant DERIVATION_DOMAIN = "FLYOVER_PEGIN_V1";

    /// @notice The encoding of the addresses returned by the derivation getters. The derived
    /// address is a base58check-encoded P2SH address, matching the construction in PegInContract.
    Encoding public constant ADDRESS_ENCODING = Encoding.BASE58;

    /// @dev Minimum BTC confirmations required for a deposit proof to gate a registration.
    /// `getBtcTransactionConfirmations` returns the confirmation count (>= 0) on success, or a
    /// negative error code when the tx/block is unknown to the Bridge. PoC uses 1.
    int256 private constant _MIN_CONFIRMATIONS = 1;
    /// @dev Length in bytes of the HASH160 (ripemd160 of sha256) digest.
    uint256 private constant _HASH160_SIZE = 20;

    /// @custom:storage-location erc7201:rsk.flyover.PegInAddressRegistry
    struct PegInAddressRegistryStorage {
        IBridge bridge;
        bool mainnet;
        uint256 count;
        bytes32 registrationRoot;
        mapping(address => uint256) registrationBlock;
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

    /// @notice Generate the base58check P2SH address for a segwit script. Exposed so the
    /// in-memory derivation can reuse `BtcUtils.getP2SHAddressFromScript` (which takes calldata)
    /// via an external self-call. Pure passthrough; not part of the frozen interface.
    /// @param segwitScript The OP_0 OP_PUSHBYTES_32 <sha256(redeemScript)> script
    /// @param mainnet Whether to encode for mainnet or testnet
    function p2shAddressFromScript(bytes calldata segwitScript, bool mainnet)
        external
        pure
        returns (bytes memory)
    {
        return BtcUtils.getP2SHAddressFromScript(segwitScript, mainnet);
    }

    /// @notice Updates the running-hash accumulator over the registered set
    /// @dev registrationRoot = keccak256(abi.encodePacked(registrationRoot, rskAddr)), order-dependent
    /// @param rskAddr The RSK address being folded into the root
    function _updateRoot(address rskAddr) private {
        PegInAddressRegistryStorage storage $ = _getStorage();
        $.registrationRoot = keccak256(abi.encodePacked($.registrationRoot, rskAddr));
    }

    /// @notice Derives the BTC deposit address for an RSK address against the current powpeg
    /// @dev Mirrors `PegInContract.validatePegInDepositAddress`, sourcing the derivation value
    /// from the RSK address plus the versioned domain tag instead of the quote hash. Reads the
    /// active powpeg redeem script live from the Bridge on every call.
    /// @param addr The RSK address
    /// @return The encoded BTC deposit address
    function _deriveAddress(address addr) private view returns (bytes memory) {
        // Self-call to satisfy BtcUtils' calldata signature while keeping the construction here.
        return this.p2shAddressFromScript(_segwitScript(addr), _getStorage().mainnet);
    }

    /// @notice Builds the segwit redeem script (OP_0 OP_PUSHBYTES_32 sha256(flyoverRedeemScript))
    /// whose P2SH wrap is the BTC deposit address for `addr`. Reads the active powpeg redeem
    /// script live from the Bridge. Shared by the address getters and the deposit-gating match.
    /// @param addr The RSK address
    /// @return The segwit script for `addr` against the current powpeg
    function _segwitScript(address addr) private view returns (bytes memory) {
        bytes32 derivationValue = _derivationValue(addr);
        bytes memory flyoverRedeemScript = bytes.concat(
            OpCodes.OP_PUSHBYTES_32,
            derivationValue,
            OpCodes.OP_DROP,
            _getStorage().bridge.getActivePowpegRedeemScript()
        );
        return bytes.concat(
            OpCodes.OP_0,
            OpCodes.OP_PUSHBYTES_32,
            sha256(flyoverRedeemScript)
        );
    }

    /// @notice Builds the on-chain P2SH output script that a BTC deposit to `addr` must carry:
    /// OP_HASH160 <ripemd160(sha256(segwitScript))> OP_EQUAL. This is the raw pkScript form a
    /// parsed tx output exposes, so the deposit-gating compares it directly against the outputs.
    /// @param addr The RSK address
    /// @return The 25-byte P2SH scriptPubkey for `addr`
    function _p2shScriptPubkey(address addr) private view returns (bytes memory) {
        bytes20 scriptHash = ripemd160(abi.encodePacked(sha256(_segwitScript(addr))));
        return bytes.concat(OpCodes.OP_HASH160, bytes1(uint8(_HASH160_SIZE)), scriptHash, OpCodes.OP_EQUAL);
    }

    /// @notice Computes the locked derivation value for an RSK address
    /// @dev derivationValue = keccak256(abi.encodePacked(DERIVATION_DOMAIN, rskAddress))
    /// @param addr The RSK address
    /// @return The derivation value
    function _derivationValue(address addr) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(DERIVATION_DOMAIN, addr));
    }

    function _getStorage() private pure returns (PegInAddressRegistryStorage storage $) {
        assembly {
            $.slot := _PEGIN_ADDRESS_REGISTRY_STORAGE
        }
    }
}
