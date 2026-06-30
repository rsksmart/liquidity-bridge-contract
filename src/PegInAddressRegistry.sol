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
contract PegInAddressRegistry is
    AccessControlDefaultAdminRulesUpgradeable,
    EmergencyPause,
    IPegInAddressRegistry
{
    struct Registration {
        uint256 blockNumber;
        address registrant;
    }

    /// @notice The version of the contract
    string public constant VERSION = "1.0.0";

    IBridge private _bridge;
    bool private _mainnet;

    bytes32 private _registrationRoot;
    uint256 private _registrationCount;
    mapping(address => Registration) private _registrations;

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
        _bridge = IBridge(bridge);
        _mainnet = mainnet;
    }

    /// @inheritdoc IPegInAddressRegistry
    function registerAddress(address addr) external override whenNotSoftPaused {
        if (addr == address(0)) revert Flyover.InvalidAddress(addr);
        if (_isRegistered(addr)) revert AlreadyRegistered(addr);

        _registrations[addr] = Registration({
            blockNumber: block.number,
            registrant: msg.sender
        });
        ++_registrationCount;
        _registrationRoot = keccak256(abi.encodePacked(_registrationRoot, addr));

        emit AddressRegistered(addr, msg.sender, _registrationRoot);
    }

    /// @inheritdoc IPegInAddressRegistry
    function getPegInAddress(
        address addr
    ) external view override returns (bytes memory derivationAddress, Encoding encoding) {
        return (_derivePegInAddress(addr), Encoding.BASE58);
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
        return (derivationAddresses, Encoding.BASE58);
    }

    /// @inheritdoc IPegInAddressRegistry
    function getRegistrationRoot() external view override returns (bytes32) {
        return _registrationRoot;
    }

    /// @inheritdoc IPegInAddressRegistry
    function isRegistered(address addr) external view override returns (bool) {
        return _isRegistered(addr);
    }

    /// @inheritdoc IPegInAddressRegistry
    function getRegistrationBlock(address addr) external view override returns (uint256) {
        return _registrations[addr].blockNumber;
    }

    /// @inheritdoc IPegInAddressRegistry
    function getRegistrant(address addr) external view override returns (address) {
        return _registrations[addr].registrant;
    }

    /// @inheritdoc IPegInAddressRegistry
    function getRegistrationCount() external view override returns (uint256) {
        return _registrationCount;
    }

    function _isRegistered(address addr) private view returns (bool) {
        return _registrations[addr].blockNumber != 0;
    }

    /// @notice Derives the Bitcoin P2SH deposit address for a Rootstock address
    /// @dev Builds the Flyover redeem script from the address hash and the active powpeg
    /// redeem script, then wraps it in a P2WSH-in-P2SH script as in `PegInContract`.
    function _derivePegInAddress(address addr) private view returns (bytes memory) {
        bytes32 derivationValue = keccak256(abi.encodePacked(addr));
        bytes memory flyoverRedeemScript = bytes.concat(
            OpCodes.OP_PUSHBYTES_32,
            derivationValue,
            OpCodes.OP_DROP,
            _bridge.getActivePowpegRedeemScript()
        );
        bytes memory segwitScript = bytes.concat(
            OpCodes.OP_0,
            OpCodes.OP_PUSHBYTES_32,
            sha256(flyoverRedeemScript)
        );
        return BtcUtils.getP2SHAddressFromScript(segwitScript, _mainnet);
    }
}
