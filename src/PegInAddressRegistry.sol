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

    /// @dev Bridge error code threshold: a positive return value is the deposited amount; any
    /// value below 1 is a bridge error / no valid deposit.
    int256 private constant _MIN_VALID_BRIDGE_RESULT = 1;
    /// @dev RSKj caps the BTC block height to a java int (int32).
    uint256 private constant _MAX_BTC_HEIGHT = uint256(uint32(type(int32).max)) - 1;

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
        if (bridge.code.length == 0) revert Flyover.NoContract(bridge);
        __AccessControlDefaultAdminRules_init(initialDelay, defaultAdmin);
        PegInAddressRegistryStorage storage $ = _getStorage();
        $.bridge = IBridge(payable(bridge));
        $.mainnet = mainnet;
    }

    /// @inheritdoc IPegInAddressRegistry
    function registerAddress(
        address addr,
        bytes calldata btcTx,
        uint256 blockHeight,
        bytes calldata merkleProof
    ) external nonReentrant override {
        PegInAddressRegistryStorage storage $ = _getStorage();
        if ($.registrationBlock[addr] != 0) {
            revert AlreadyRegistered(addr);
        }
        if (blockHeight > _MAX_BTC_HEIGHT) {
            revert Flyover.Overflow(_MAX_BTC_HEIGHT);
        }

        // The derivation value is the same fast-bridge derivation argument the Bridge uses to
        // reconstruct the flyover redeem script, so a positive result means the BTC tx pays the
        // address derived for `addr`. Permissionless: msg.sender is never checked against addr.
        bytes32 derivationValue = _derivationValue(addr);
        int256 bridgeResult = $.bridge.registerFastBridgeBtcTransaction(
            btcTx,
            blockHeight,
            merkleProof,
            derivationValue,
            // No user/LP refund or call semantics in the registry: register the deposit only.
            new bytes(0),
            payable(this),
            new bytes(0),
            false
        );
        if (bridgeResult < _MIN_VALID_BRIDGE_RESULT) {
            revert InvalidDepositProof(addr, bridgeResult);
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
        PegInAddressRegistryStorage storage $ = _getStorage();
        bytes32 derivationValue = _derivationValue(addr);
        bytes memory flyoverRedeemScript = bytes.concat(
            OpCodes.OP_PUSHBYTES_32,
            derivationValue,
            OpCodes.OP_DROP,
            $.bridge.getActivePowpegRedeemScript()
        );
        bytes memory segwitScript = bytes.concat(
            OpCodes.OP_0,
            OpCodes.OP_PUSHBYTES_32,
            sha256(flyoverRedeemScript)
        );
        // Self-call to satisfy BtcUtils' calldata signature while keeping the construction here.
        return this.p2shAddressFromScript(segwitScript, $.mainnet);
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
