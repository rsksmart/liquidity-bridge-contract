// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PegInAddressRegistry} from "../../src/PegInAddressRegistry.sol";
import {PegInAddressRegistryHarness} from "./PegInAddressRegistryHarness.sol";
import {RegistryBridgeMock} from "./RegistryBridgeMock.sol";
import {PegInDerivation} from "../../src/libraries/PegInDerivation.sol";
import {PauseRegistry} from "../../src/PauseRegistry.sol";
import {IPauseRegistry} from "../../src/interfaces/IPauseRegistry.sol";
import {BtcUtils} from "@rsksmart/btc-transaction-solidity-helper/contracts/BtcUtils.sol";

/// @title PegInRegistryTestBase
/// @notice Shared proxy deploy + register helpers for PegInAddressRegistry tests.
abstract contract PegInRegistryTestBase is Test {
    uint48 internal constant ADMIN_DELAY = 0;

    address internal constant PEGIN_CONTRACT =
        address(0x00000000000000000000000000000000C0FFEE01);

    bytes32 internal constant BLOCK_HASH = bytes32(uint256(0xBEEF));
    uint256 internal constant MERKLE_PATH = 0;

    address internal owner = address(0xA11CE);
    address internal stranger = address(0xB0B);

    PegInAddressRegistryHarness internal registry;
    RegistryBridgeMock internal bridge;
    PauseRegistry internal pauseRegistry;

    function _deployPauseRegistry() internal {
        PauseRegistry impl = new PauseRegistry();
        bytes memory initData = abi.encodeCall(PauseRegistry.initialize, (ADMIN_DELAY, owner));
        pauseRegistry = PauseRegistry(address(new ERC1967Proxy(address(impl), initData)));
    }

    function _deploy(bool mainnet) internal {
        bridge = new RegistryBridgeMock();
        _deployPauseRegistry();
        PegInAddressRegistryHarness impl = new PegInAddressRegistryHarness();
        bytes memory initData = abi.encodeCall(
            PegInAddressRegistry.initialize,
            (owner, ADMIN_DELAY, address(bridge), mainnet, IPauseRegistry(address(pauseRegistry)))
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        registry = PegInAddressRegistryHarness(payable(address(proxy)));
        vm.prank(owner);
        registry.setPegInContract(PEGIN_CONTRACT);
    }

    function _deployUnwired(
        bool mainnet
    ) internal returns (PegInAddressRegistryHarness r) {
        if (address(bridge) == address(0)) bridge = new RegistryBridgeMock();
        if (address(pauseRegistry) == address(0)) _deployPauseRegistry();
        PegInAddressRegistryHarness impl = new PegInAddressRegistryHarness();
        bytes memory initData = abi.encodeCall(
            PegInAddressRegistry.initialize,
            (owner, ADMIN_DELAY, address(bridge), mainnet, IPauseRegistry(address(pauseRegistry)))
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        r = PegInAddressRegistryHarness(payable(address(proxy)));
    }

    function _seedRegistration(
        address addr,
        address registrant,
        uint96 registrationBlock
    ) internal {
        registry.harness_seedRegistration(addr, registrant, registrationBlock);
    }

    function _seedRegistrationRoot(bytes32 root) internal {
        registry.harness_seedRegistrationRoot(root);
    }

    function _addressVersionByte(
        bytes memory payload
    ) internal pure returns (bytes1) {
        require(payload.length > 0, "empty payload");
        return payload[0];
    }

    function _depositPkScript(
        address rskAddr
    ) internal view returns (bytes memory) {
        bytes memory powpeg = bridge.getActivePowpegRedeemScript();
        bytes32 dv = PegInDerivation.derivationValue(rskAddr, PEGIN_CONTRACT);
        bytes memory redeem = PegInDerivation.flyoverRedeemScript(dv, powpeg);
        bytes20 scriptHash = PegInDerivation.flyoverScriptHash(redeem);
        return PegInDerivation.p2shScriptPubkey(scriptHash);
    }

    function _buildDepositTx(
        bytes memory pkScript,
        uint64 value
    ) internal pure returns (bytes memory) {
        bytes memory valueLe = new bytes(8);
        uint64 v = value;
        for (uint256 i = 0; i < 8; ++i) {
            valueLe[i] = bytes1(uint8(v & 0xFF));
            v >>= 8;
        }
        return
            abi.encodePacked(
                hex"01000000",
                hex"01",
                bytes32(uint256(1)),
                hex"00000000",
                hex"00",
                hex"ffffffff",
                hex"01",
                valueLe,
                bytes1(uint8(pkScript.length)),
                pkScript,
                hex"00000000"
            );
    }

    function _emptyHashes() internal pure returns (bytes32[] memory) {
        return new bytes32[](0);
    }

    function _programProof(
        bytes memory txBytes,
        bytes32 blockHash,
        uint256 path,
        bytes32[] memory hashes
    ) internal {
        bridge.setExpectedProof(
            BtcUtils.hashBtcTx(txBytes),
            blockHash,
            path,
            hashes
        );
    }

    function _register(address rskAddr, uint64 value, address caller) internal {
        bytes memory txBytes = _buildDepositTx(
            _depositPkScript(rskAddr),
            value
        );
        bytes32[] memory hashes = _emptyHashes();
        _programProof(txBytes, BLOCK_HASH, MERKLE_PATH, hashes);
        vm.prank(caller);
        registry.registerAddress(
            rskAddr,
            txBytes,
            BLOCK_HASH,
            MERKLE_PATH,
            hashes
        );
    }

    function _foldRoot(
        bytes32 prevRoot,
        address rskAddr
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(prevRoot, rskAddr));
    }
}
