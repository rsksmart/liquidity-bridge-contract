// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {
    AccessControlDefaultAdminRulesUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {BtcUtils} from "@rsksmart/btc-transaction-solidity-helper/contracts/BtcUtils.sol";
import {OpCodes} from "@rsksmart/btc-transaction-solidity-helper/contracts/OpCodes.sol";
import {EmergencyPause} from "./EmergencyPause/EmergencyPause.sol";
import {IBridge} from "./interfaces/IBridge.sol";
import {IPauseRegistry} from "./interfaces/IPauseRegistry.sol";
import {IPegInAddressRegistry} from "./interfaces/IPegInAddressRegistry.sol";
import {Flyover} from "./libraries/Flyover.sol";

/// @title PegInAddressRegistry
/// @notice Maintains registered Flyover peg-in Rootstock addresses and derives the
/// corresponding Bitcoin deposit addresses for the current powpeg composition
/// @dev Uses ERC-7201 namespaced storage for upgrade-safe state layout
contract PegInAddressRegistry is
    AccessControlDefaultAdminRulesUpgradeable,
    EmergencyPause,
    IPegInAddressRegistry
{
    struct Registration {
        uint256 blockNumber;
        address registrant;
    }

    /// @custom:storage-location erc7201:rsk.flyover.PegInAddressRegistry
    struct PegInAddressRegistryStorage {
        IBridge bridge;
        bool mainnet;
        bytes32 registrationRoot;
        uint256 registrationCount;
        mapping(address => Registration) registrations;
    }

    /// @notice The version of the contract
    string public constant VERSION = "1.0.0";

    Encoding private constant _ENCODING = Encoding.BASE58;

    // ERC-7201: keccak256(abi.encode(uint256(keccak256("rsk.flyover.PegInAddressRegistry")) - 1)) &
    // ~bytes32(uint256(0xff))
    bytes32 private constant _PEG_IN_ADDRESS_REGISTRY_STORAGE =
        0x0704e3acad2c0308b9997bc861208a21efddaa710005747040bdddc7b9400f00;

    /// @notice Emitted when an address is already registered
    /// @param addr The Rootstock address that was already registered
    error AlreadyRegistered(address addr);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param defaultAdmin The default admin of the contract
    /// @param bridge The Rootstock bridge contract
    /// @param mainnet Whether the contract derives mainnet or testnet BTC addresses
    /// @param pauseRegistry The central PauseRegistry for pause state
    // solhint-disable-next-line comprehensive-interface
    function initialize(
        address defaultAdmin,
        address payable bridge,
        bool mainnet,
        address pauseRegistry
    ) external initializer {
        if (address(pauseRegistry).code.length == 0) {
            revert Flyover.NoContract(address(pauseRegistry));
        }
        __AccessControlDefaultAdminRules_init(0, defaultAdmin);
        __EmergencyPause_init(IPauseRegistry(pauseRegistry));

        PegInAddressRegistryStorage storage $ = _getPegInAddressRegistryStorage();
        $.bridge = IBridge(bridge);
        $.mainnet = mainnet;
    }

    /// @inheritdoc IPegInAddressRegistry
    function registerAddress(address addr) external override whenNotSoftPaused {
        if (addr == address(0)) revert Flyover.InvalidAddress(addr);

        PegInAddressRegistryStorage storage $ = _getPegInAddressRegistryStorage();
        if (_isRegistered($, addr)) revert AlreadyRegistered(addr);

        $.registrations[addr] = Registration({
            blockNumber: block.number,
            registrant: msg.sender
        });
        ++$.registrationCount;
        $.registrationRoot = keccak256(abi.encodePacked($.registrationRoot, addr));

        emit AddressRegistered(addr, msg.sender, $.registrationRoot);
    }

    /// @inheritdoc IPegInAddressRegistry
    function getPegInAddress(
        address addr
    ) external view override returns (bytes memory derivationAddress, Encoding encoding) {
        return (_derivePegInAddress(addr), _ENCODING);
    }

    /// @inheritdoc IPegInAddressRegistry
    function getPegInAddresses(
        address[] calldata addrs
    ) external view override returns (bytes[] memory derivationAddresses, Encoding encoding) {
        uint addressCount = addrs.length;
        derivationAddresses = new bytes[](addressCount);
        for (uint256 i = 0; i < addressCount; ++i) {
            derivationAddresses[i] = _derivePegInAddress(addrs[i]);
        }
        return (derivationAddresses, _ENCODING);
    }

    /// @inheritdoc IPegInAddressRegistry
    function getRegistrationRoot() external view override returns (bytes32) {
        return _getPegInAddressRegistryStorage().registrationRoot;
    }

    /// @inheritdoc IPegInAddressRegistry
    function isRegistered(address addr) external view override returns (bool) {
        return _isRegistered(_getPegInAddressRegistryStorage(), addr);
    }

    /// @inheritdoc IPegInAddressRegistry
    function getRegistrationBlock(address addr) external view override returns (uint256) {
        return _getPegInAddressRegistryStorage().registrations[addr].blockNumber;
    }

    /// @inheritdoc IPegInAddressRegistry
    function getRegistrant(address addr) external view override returns (address) {
        return _getPegInAddressRegistryStorage().registrations[addr].registrant;
    }

    /// @inheritdoc IPegInAddressRegistry
    function getRegistrationCount() external view override returns (uint256) {
        return _getPegInAddressRegistryStorage().registrationCount;
    }

    function _isRegistered(
        PegInAddressRegistryStorage storage $,
        address addr
    ) private view returns (bool) {
        return $.registrations[addr].blockNumber != 0;
    }

    /// @notice Derives the Bitcoin P2SH deposit address for a Rootstock address
    /// @dev Builds the Flyover redeem script from the address hash and the active powpeg
    /// redeem script, then wraps it in a P2WSH-in-P2SH script as in `PegInContract`.
    function _derivePegInAddress(address addr) private view returns (bytes memory) {
        PegInAddressRegistryStorage storage $ = _getPegInAddressRegistryStorage();
        bytes32 derivationValue = keccak256(abi.encodePacked(addr));
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
        return BtcUtils.getP2SHAddressFromScript(segwitScript, $.mainnet);
    }

    function _getPegInAddressRegistryStorage()
        private
        pure
        returns (PegInAddressRegistryStorage storage $)
    {
        assembly {
            $.slot := _PEG_IN_ADDRESS_REGISTRY_STORAGE
        }
    }
}
