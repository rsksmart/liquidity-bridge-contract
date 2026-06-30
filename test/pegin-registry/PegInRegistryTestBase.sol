// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PegInAddressRegistry} from "../../src/PegInAddressRegistry.sol";
import {RegistryBridgeMock} from "./RegistryBridgeMock.sol";

/// @title PegInRegistryTestBase
/// @notice Shared setup for the PegInAddressRegistry test suite: deploys the registry behind
/// an ERC1967 proxy against a swappable bridge mock, and builds serialized BTC txs whose output
/// pays the P2SH address derived for a given RSK address (the read-only deposit-gating input).
abstract contract PegInRegistryTestBase is Test {
    uint48 internal constant ADMIN_DELAY = 0;

    address internal owner = address(0xA11CE);

    PegInAddressRegistry internal registry;
    RegistryBridgeMock internal bridge;

    function _deploy(bool mainnet) internal {
        bridge = new RegistryBridgeMock();
        PegInAddressRegistry impl = new PegInAddressRegistry();
        bytes memory initData = abi.encodeCall(
            PegInAddressRegistry.initialize,
            (owner, ADMIN_DELAY, address(bridge), mainnet)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        registry = PegInAddressRegistry(payable(address(proxy)));
    }

    /// @notice The locked derivation value mixed into the derived BTC deposit address.
    function _derivationValue(address addr) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(registryDomain(), addr));
    }

    function registryDomain() internal pure returns (bytes memory) {
        return "FLYOVER_PEGIN_V1";
    }

    /// @notice Extracts the 20-byte HASH160 from the base58check P2SH address the registry derives
    /// for `addr`. The derived address is versionByte(1) || hash160(20) || checksum(4).
    function _derivedHash160(address addr) internal view returns (bytes20) {
        (bytes memory a, ) = registry.getPegInAddress(addr);
        require(a.length == 25, "unexpected derived address length");
        bytes20 hash160;
        assembly {
            // skip length word (32) + version byte (1) => offset 33
            hash160 := mload(add(a, 33))
        }
        return hash160;
    }

    /// @notice Builds the 25-byte P2SH scriptPubkey (OP_HASH160 <20> OP_EQUAL) for `addr`.
    function _derivedScriptPubkey(address addr) internal view returns (bytes memory) {
        return bytes.concat(hex"a914", _derivedHash160(addr), hex"87");
    }

    /// @notice Builds a minimal serialized (non-witness) BTC tx with a single P2SH output paying
    /// `scriptPubkey`. Shape: version | 1 input (null) | 1 output | locktime.
    function _btcTxPaying(bytes memory scriptPubkey) internal pure returns (bytes memory) {
        return bytes.concat(
            hex"02000000",                 // version
            hex"01",                       // input count
            bytes32(0),                    // prev txid
            hex"00000000",                 // prev vout
            hex"00",                       // scriptSig length (empty)
            hex"ffffffff",                 // sequence
            hex"01",                       // output count
            hex"00ca9a3b00000000",         // value (1 BTC, little-endian)
            bytes1(uint8(scriptPubkey.length)),
            scriptPubkey,
            hex"00000000"                  // locktime
        );
    }

    /// @notice Builds a serialized BTC tx whose single output pays the address derived for `addr`.
    function _btcTxForAddr(address addr) internal view returns (bytes memory) {
        return _btcTxPaying(_derivedScriptPubkey(addr));
    }

    /// @notice Registers `addr` (as `caller`) with a tx paying the derived address; the default
    /// mock returns enough confirmations.
    function _registerWithDeposit(address addr, address caller) internal {
        bytes32[] memory branches;
        vm.prank(caller);
        registry.registerAddress(addr, _btcTxForAddr(addr), bytes32(0), 0, branches);
    }
}
