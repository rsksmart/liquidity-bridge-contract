// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IBridge} from "./interfaces/IBridge.sol";
import {IPegInAddressRegistry} from "./interfaces/IPegInAddressRegistry.sol";
import {Flyover} from "./libraries/Flyover.sol";
import {PegInDerivation} from "./libraries/PegInDerivation.sol";

/// @title PegInAddressRegistry
/// @notice Upgradeable registry that derives a static BTC deposit address from an RSK address
/// against the current powpeg and exposes registration lookups.
/// @dev Exposes derivation and registration views. `registerAddress` reverts with
/// {RegisterAddressNotImplemented}. Deposit-address bytes are composed from {PegInDerivation}
/// and the live powpeg redeem script returned by {IBridge}.
/// @author Rootstock Labs(TravellerOnTheRun)
contract PegInAddressRegistry is AccessControlDefaultAdminRulesUpgradeable, ReentrancyGuard, IPegInAddressRegistry {
    /// @notice The version of the contract
    string public constant VERSION = "1.0.0";

    /// @notice Maximum batch size for `getPegInAddresses`.
    uint256 public constant MAX_PEGIN_ADDRESS_BATCH = 100;

    /// @notice The encoding of addresses returned by the derivation getters.
    Encoding public constant ADDRESS_ENCODING = Encoding.BASE58;

    /// @custom:storage-location erc7201:rsk.flyover.PegInAddressRegistry
    struct PegInAddressRegistryStorage {
        IBridge bridge;
        bool mainnet;
        bytes32 registrationRoot;
        mapping(address => Registration) registrations;
        address pegInContract;
    }

    // ERC-7201: keccak256(abi.encode(uint256(keccak256("rsk.flyover.PegInAddressRegistry")) - 1)) &
    // ~bytes32(uint256(0xff))
    bytes32 private constant _PEGIN_ADDRESS_REGISTRY_STORAGE =
        0x0704e3acad2c0308b9997bc861208a21efddaa710005747040bdddc7b9400f00;

    /// @notice Raised when an address derivation is attempted before the PegInContract is wired.
    error PegInContractNotSet();

    /// @notice Raised when a batch request exceeds {MAX_PEGIN_ADDRESS_BATCH}.
    error BatchTooLarge(uint256 requested, uint256 max);

    /// @notice Raised when `registerAddress` is called while registration writes are unavailable.
    error RegisterAddressNotImplemented();

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
    /// @param mainnet Whether the derived addresses target mainnet or testnet
    // solhint-disable-next-line comprehensive-interface
    function initialize(address defaultAdmin, uint48 initialDelay, address bridge, bool mainnet) external initializer {
        if (bridge == address(0)) revert Flyover.NoContract(bridge);
        __AccessControlDefaultAdminRules_init(initialDelay, defaultAdmin);
        PegInAddressRegistryStorage storage $ = _getStorage();
        $.bridge = IBridge(payable(bridge));
        $.mainnet = mainnet;
    }

    /// @inheritdoc IPegInAddressRegistry
    function registerAddress(address, bytes calldata, bytes32, uint256, bytes32[] calldata) external pure override {
        revert RegisterAddressNotImplemented();
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
        uint256 length = addrs.length;
        if (length > MAX_PEGIN_ADDRESS_BATCH) {
            revert BatchTooLarge(length, MAX_PEGIN_ADDRESS_BATCH);
        }
        derivationAddresses = new bytes[](length);
        for (uint256 i = 0; i < length; ++i) {
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

    /// @notice Returns the PegInContract mixed into the derivation (zero if unset).
    // solhint-disable-next-line comprehensive-interface
    function getPegInContract() external view returns (address) {
        return _getStorage().pegInContract;
    }

    /// @notice Derives the BTC deposit address for an RSK address against the current powpeg.
    function _deriveAddress(address addr) private view returns (bytes memory) {
        PegInAddressRegistryStorage storage $ = _getStorage();
        address pegInContract = $.pegInContract;
        if (pegInContract == address(0)) revert PegInContractNotSet();

        bytes32 derivationValue = PegInDerivation.derivationValue(addr, pegInContract);
        bytes memory redeemScript = PegInDerivation.flyoverRedeemScript(
            derivationValue,
            // TODO: instead pass the bridge address
            // (library changes the construction)
            $.bridge.getActivePowpegRedeemScript()
        );
        bytes20 scriptHash = PegInDerivation.flyoverScriptHash(redeemScript);
        return PegInDerivation.depositAddressPayload(scriptHash, $.mainnet);
    }

    function _getStorage() internal pure returns (PegInAddressRegistryStorage storage $) {
        assembly {
            $.slot := _PEGIN_ADDRESS_REGISTRY_STORAGE
        }
    }
}
