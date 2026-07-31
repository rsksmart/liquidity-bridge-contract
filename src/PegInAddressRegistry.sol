// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {BtcUtils} from "@rsksmart/btc-transaction-solidity-helper/contracts/BtcUtils.sol";
import {EmergencyPause} from "./EmergencyPause/EmergencyPause.sol";
import {IBridge} from "./interfaces/IBridge.sol";
import {IPauseRegistry} from "./interfaces/IPauseRegistry.sol";
import {IPegInAddressRegistry} from "./interfaces/IPegInAddressRegistry.sol";
import {Flyover} from "./libraries/Flyover.sol";
import {PegInDerivation} from "./libraries/PegInDerivation.sol";

/// @title PegInAddressRegistry
/// @notice Upgradeable registry that derives a static BTC deposit address from an RSK address
/// against the current powpeg and exposes registration lookups.
/// @dev Exposes derivation and registration views. Deposit-address bytes are composed from
/// {PegInDerivation} and the live powpeg redeem script returned by {IBridge}.
/// @author Rootstock Labs(TravellerOnTheRun)
contract PegInAddressRegistry is
    AccessControlDefaultAdminRulesUpgradeable,
    EmergencyPause,
    ReentrancyGuard,
    IPegInAddressRegistry
{
    /// @custom:storage-location erc7201:rsk.flyover.PegInAddressRegistry
    struct PegInAddressRegistryStorage {
        IBridge bridge;
        bool isMainnet;
        bytes32 registrationRoot;
        mapping(address => Registration) registrations;
        address pegInContract;
    }

    /// @notice The version of the contract
    string public constant VERSION = "1.0.0";

    /// @notice Minimum deposit output value (satoshis) required to register an address.
    uint256 public constant MIN_DEPOSIT_SATS = 546;

    /// @notice Minimum BTC confirmations required for a deposit proof to gate registration.
    /// @dev Walkthrough step 8 / D8 and the S3.2 ticket require confirmations ≥ 1. Named so
    /// the floor can be raised without hunting magic numbers.
    int256 public constant MIN_CONFIRMATIONS = 1;

    /// @notice Maximum batch size for `getPegInAddresses`.
    uint256 public constant MAX_PEGIN_ADDRESS_BATCH = 100;

    /// @notice The encoding of addresses returned by the derivation getters.
    Encoding public constant ADDRESS_ENCODING = Encoding.BASE58;

    // ERC-7201: keccak256(abi.encode(uint256(keccak256("rsk.flyover.PegInAddressRegistry")) - 1)) &
    // ~bytes32(uint256(0xff))
    bytes32 private constant _PEGIN_ADDRESS_REGISTRY_STORAGE =
        0x0704e3acad2c0308b9997bc861208a21efddaa710005747040bdddc7b9400f00;

    /// @notice Emitted when the PegInContract mixed into the derivation is set.
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
    /// @param isMainnet Whether the derived addresses target mainnet or testnet
    /// @param pauseRegistry_ The central PauseRegistry for pause state
    // solhint-disable-next-line comprehensive-interface
    function initialize(
        address defaultAdmin,
        uint48 initialDelay,
        address bridge,
        bool isMainnet,
        IPauseRegistry pauseRegistry_
    ) external initializer {
        if (bridge == address(0)) revert Flyover.NoContract(bridge);
        if (address(pauseRegistry_).code.length == 0) revert Flyover.NoContract(address(pauseRegistry_));
        __AccessControlDefaultAdminRules_init(initialDelay, defaultAdmin);
        __EmergencyPause_init(pauseRegistry_);
        PegInAddressRegistryStorage storage $ = _getStorage();
        $.bridge = IBridge(payable(bridge));
        $.isMainnet = isMainnet;
    }

    /// @notice Sets the PegInContract mixed into the deposit-address derivation.
    /// @param pegInContract The PegInContract address
    // solhint-disable-next-line comprehensive-interface
    function setPegInContract(address pegInContract) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        if (pegInContract == address(0)) {
            revert Flyover.NoContract(pegInContract);
        }
        PegInAddressRegistryStorage storage $ = _getStorage();
        emit PegInContractSet($.pegInContract, pegInContract);
        $.pegInContract = pegInContract;
    }

    /// @inheritdoc IPegInAddressRegistry
    function registerAddress(
        address rskAddr,
        bytes calldata btcTxSerialized,
        bytes32 btcBlockHash,
        uint256 merkleBranchPath,
        bytes32[] calldata merkleBranchHashes
    ) external override whenNotSoftPaused nonReentrant {
        PegInAddressRegistryStorage storage $ = _getStorage();

        if ($.registrations[rskAddr].registrationBlock != 0) {
            revert AddressAlreadyRegistered(rskAddr);
        }

        address pegInContract = $.pegInContract;
        if (pegInContract == address(0)) revert PegInContractNotSet();

        bytes memory expectedPkScript = _expectedDepositPkScript(rskAddr, pegInContract, $.bridge, $.isMainnet);
        uint64 depositValue = _matchedDepositValue(btcTxSerialized, expectedPkScript, rskAddr);

        if (depositValue < MIN_DEPOSIT_SATS) {
            revert DepositBelowMinimum(depositValue, MIN_DEPOSIT_SATS);
        }

        bytes32 btcTxHash = BtcUtils.hashBtcTx(btcTxSerialized);
        int256 confirmations =
            $.bridge.getBtcTransactionConfirmations(btcTxHash, btcBlockHash, merkleBranchPath, merkleBranchHashes);
        if (confirmations < MIN_CONFIRMATIONS) {
            revert DepositNotConfirmed(btcTxHash);
        }

        $.registrations[rskAddr] = Registration({registrant: msg.sender, registrationBlock: uint96(block.number)});
        bytes32 newRoot = keccak256(abi.encodePacked($.registrationRoot, rskAddr));
        $.registrationRoot = newRoot;
        emit AddressRegistered(rskAddr, msg.sender, newRoot);
    }

    /// @inheritdoc IPegInAddressRegistry
    function getPegInAddress(address addr) external view override returns (bytes memory, Encoding) {
        PegInAddressRegistryStorage storage $ = _getStorage();
        address pegInContract = $.pegInContract;
        if (pegInContract == address(0)) revert PegInContractNotSet();
        // The active powpeg redeem script is invariant across a single call, so it is
        // read once here and reused for the derivation.
        bytes memory powpegRedeemScript = $.bridge.getActivePowpegRedeemScript();
        return (_deriveAddress(addr, pegInContract, powpegRedeemScript, $.isMainnet), ADDRESS_ENCODING);
    }

    /// @inheritdoc IPegInAddressRegistry
    function getPegInAddresses(address[] calldata addrs)
        external
        view
        override
        returns (bytes[] memory derivationAddresses, Encoding encoding)
    {
        uint256 length = addrs.length;
        if (length > MAX_PEGIN_ADDRESS_BATCH) {
            revert BatchTooLarge(length, MAX_PEGIN_ADDRESS_BATCH);
        }
        PegInAddressRegistryStorage storage $ = _getStorage();
        address pegInContract = $.pegInContract;
        if (pegInContract == address(0)) revert PegInContractNotSet();
        // Read the invariant derivation inputs once, before the loop, so the batch performs a
        // single external bridge call and derives every address against a consistent powpeg.
        bytes memory powpegRedeemScript = $.bridge.getActivePowpegRedeemScript();
        bool isMainnet = $.isMainnet;
        derivationAddresses = new bytes[](length);
        for (uint256 i = 0; i < length; ++i) {
            derivationAddresses[i] = _deriveAddress(addrs[i], pegInContract, powpegRedeemScript, isMainnet);
        }
        encoding = ADDRESS_ENCODING;
    }

    /// @inheritdoc IPegInAddressRegistry
    function getRegistrationRoot() external view override returns (bytes32) {
        return _getStorage().registrationRoot;
    }

    /// @inheritdoc IPegInAddressRegistry
    function isRegistered(address addr) external view override returns (bool) {
        return _getStorage().registrations[addr].registrationBlock != 0;
    }

    /// @inheritdoc IPegInAddressRegistry
    function getRegistration(address addr) external view override returns (Registration memory) {
        return _getStorage().registrations[addr];
    }

    /// @notice Returns the bridge the registry derives against
    // solhint-disable-next-line comprehensive-interface
    function getBridge() external view returns (IBridge) {
        return _getStorage().bridge;
    }

    /// @notice Returns the PegInContract mixed into the derivation (zero if unset).
    // solhint-disable-next-line comprehensive-interface
    function getPegInContract() external view returns (address) {
        return _getStorage().pegInContract;
    }

    /// @notice Derives the on-chain P2SH scriptPubkey for a deposit output match.
    /// @dev Reads the live powpeg script and hands the composition to
    /// {PegInDerivation-expectedDepositPkScript}. The registry holds no derivation of its own:
    /// `PegInContract.requestPegIn` matches deposits against that same helper, so the script that
    /// gates registration is the script that fixes the peg-in amount.
    /// @param isMainnet Whether the derivation targets mainnet or testnet — the BTC placeholders
    /// mixed into the value are per-network, so this must match the flag used at issuance
    function _expectedDepositPkScript(address rskAddr, address pegInContract, IBridge bridge_, bool isMainnet)
        private
        view
        returns (bytes memory)
    {
        return PegInDerivation.expectedDepositPkScript(
            rskAddr, pegInContract, bridge_.getActivePowpegRedeemScript(), isMainnet
        );
    }

    /// @notice Returns the satoshi value of the output paying the derived deposit script.
    /// @dev Thin wrapper over {PegInDerivation-matchedDepositValue} that turns the library's
    /// found flag into the registry's own named error.
    function _matchedDepositValue(bytes calldata btcTxSerialized, bytes memory expectedPkScript, address rskAddr)
        private
        pure
        returns (uint64 depositValue)
    {
        bool found;
        (depositValue, found) = PegInDerivation.matchedDepositValue(btcTxSerialized, expectedPkScript);
        if (!found) {
            revert DepositOutputNotFound(rskAddr);
        }
    }

    /// @notice Derives the BTC deposit address for an RSK address against a supplied powpeg script.
    /// @dev Callers must fetch the invariant derivation inputs (pegInContract, powpeg redeem script
    /// and mainnet flag) once and pass them in, keeping the external bridge call out of any loop.
    /// @param addr The RSK address the deposit address is derived for
    /// @param pegInContract The PegInContract mixed into the derivation (must be non-zero)
    /// @param powpegRedeemScript The active powpeg redeem script returned by the bridge
    /// @param isMainnet Whether the derived address targets mainnet or testnet
    function _deriveAddress(address addr, address pegInContract, bytes memory powpegRedeemScript, bool isMainnet)
        private
        pure
        returns (bytes memory)
    {
        bytes32 derivationValue = PegInDerivation.derivationValue(addr, pegInContract, isMainnet);
        // TODO(FLY-2436): pass the bridge address once the derivation library owns script construction
        bytes memory redeemScript = PegInDerivation.flyoverRedeemScript(derivationValue, powpegRedeemScript);
        bytes20 scriptHash = PegInDerivation.flyoverScriptHash(redeemScript);
        return PegInDerivation.depositAddressPayload(scriptHash, isMainnet);
    }

    function _getStorage() internal pure returns (PegInAddressRegistryStorage storage $) {
        assembly {
            $.slot := _PEGIN_ADDRESS_REGISTRY_STORAGE
        }
    }
}
