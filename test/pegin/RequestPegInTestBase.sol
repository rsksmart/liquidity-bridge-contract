// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInTestBase} from "./PegInTestBase.sol";
import {FlyoverConfigurationsMock} from "./FlyoverConfigurationsMock.sol";
import {PegInContract} from "../../src/PegInContract.sol";
import {PegInAddressRegistryHarness} from "../pegin-registry/PegInAddressRegistryHarness.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";
import {PegInDerivation} from "../../src/libraries/PegInDerivation.sol";
import {Quotes} from "../../src/libraries/Quotes.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BtcUtils} from "@rsksmart/btc-transaction-solidity-helper/contracts/BtcUtils.sol";

/// @title Base for commit-first requestPegIn tests
/// @notice Deploys and wires a PegInContract against a real PegInAddressRegistry (seeded through
/// its harness) and a settable FlyoverConfigurationsMock, and reads the private claim record
/// through storage slots (no production getter exists on the implementation under test).
abstract contract RequestPegInTestBase is PegInTestBase {
    /// @dev Storage slot of PegInContract._pegInClaims under the lockfile-pinned OpenZeppelin
    /// 5.5.0 remapping in foundry.toml (contracts package under node_modules). OZ 5.5+ stores
    /// ReentrancyGuard in an ERC-7201 namespace, so claims sit at slot 10 (not 11). Verify with
    /// `forge inspect PegInContract storageLayout` after `npm ci`. A claim lives at
    /// keccak256(abi.encode(pegInId, PEGIN_CLAIMS_BASE_SLOT)); the struct has no packing, so each
    /// uint256 field starts a fresh slot after the 20-byte address.
    uint256 internal constant PEGIN_CLAIMS_BASE_SLOT = 10;

    uint256 internal constant BASIS_POINTS = 10000;

    uint256 internal constant DEFAULT_FIXED_FEE = 0.001 ether;
    uint256 internal constant DEFAULT_PERCENTAGE_FEE = 100; // 1%
    uint256 internal constant DEFAULT_MAX_AMOUNT = 100 ether;
    uint256 internal constant DEFAULT_TIER_CONFIRMATIONS = 10;

    PegInAddressRegistryHarness internal registry;
    FlyoverConfigurationsMock internal configurations;

    address internal claimer;
    address internal rskUser;

    uint256 internal constant DEFAULT_AMOUNT = 5 ether;

    /// @dev Varies the deposit transaction's input outpoint, and therefore its txid, without
    /// touching the output being matched. Tests that need two distinct pegInIds for the same
    /// destination and amount pass different nonces.
    uint256 internal constant DEFAULT_TX_NONCE = 1;

    function setUp() public virtual {
        deployPegInContract();

        registry = _deployRegistryHarness();
        configurations = new FlyoverConfigurationsMock();
        _applyDefaultConfiguration();

        vm.prank(owner);
        pegInContract.setPegInDependencies(
            address(registry),
            address(configurations)
        );

        claimer = makeAddr("claimer");
        rskUser = makeAddr("rskUser");
        vm.deal(claimer, 100 ether);

        registry.harness_seedRegistration(rskUser, makeAddr("registrant"), 1);
        bridgeMock.setConfirmations(int256(DEFAULT_TIER_CONFIRMATIONS));
    }

    // ---- deployment helpers ----

    function _deployRegistryHarness()
        internal
        returns (PegInAddressRegistryHarness harness)
    {
        PegInAddressRegistryHarness implementation = new PegInAddressRegistryHarness();
        bytes memory initData = abi.encodeCall(
            implementation.initialize,
            (owner, uint48(0), address(bridgeMock), false, pauseRegistry)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        harness = PegInAddressRegistryHarness(payable(address(proxy)));
    }

    function _applyDefaultConfiguration() internal {
        configurations.setFee(DEFAULT_FIXED_FEE, DEFAULT_PERCENTAGE_FEE);
        configurations.setAmountBounds(TEST_MIN_PEGIN, DEFAULT_MAX_AMOUNT);
        IFlyoverConfigurations.ConfirmationTier[]
            memory tiers = new IFlyoverConfigurations.ConfirmationTier[](1);
        tiers[0] = IFlyoverConfigurations.ConfirmationTier({
            maxAmount: type(uint256).max,
            confirmations: DEFAULT_TIER_CONFIRMATIONS
        });
        configurations.setConfirmationTiers(tiers);
    }

    /// @notice Replaces the single flat tier with a low tier up to `lowTierMaxAmount` and a high
    /// tier above it, so tests can prove the tier is chosen by the amount READ off the deposit.
    function _applyTwoTierConfiguration(
        uint256 lowTierMaxAmount,
        uint256 lowTierConfirmations,
        uint256 highTierConfirmations
    ) internal {
        IFlyoverConfigurations.ConfirmationTier[]
            memory tiers = new IFlyoverConfigurations.ConfirmationTier[](2);
        tiers[0] = IFlyoverConfigurations.ConfirmationTier({
            maxAmount: lowTierMaxAmount,
            confirmations: lowTierConfirmations
        });
        tiers[1] = IFlyoverConfigurations.ConfirmationTier({
            maxAmount: type(uint256).max,
            confirmations: highTierConfirmations
        });
        configurations.setConfirmationTiers(tiers);
    }

    /// @notice Deploys a second PegInContract with its dependencies left unset
    function _deployUnwiredPegInContract() internal returns (PegInContract) {
        return deployPegInContract(false);
    }

    // ---- claim helpers ----

    function _pegInId(
        address rskAddr,
        bytes32 btcTxHash
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(rskAddr, btcTxHash));
    }

    /// @notice Exposes BtcUtils.hashBtcTx to the memory-held fixtures. The library takes
    /// calldata, so the tests reach it through an external self-call rather than
    /// re-implementing the txid.
    /// @dev Being an external self-call, this CONSUMES a pending vm.prank. Call it (and the
    /// helpers below that wrap it) before vm.prank, never inside a vm.expectRevert payload that
    /// follows one, or the call under test runs as the test contract instead of the pranked
    /// sender and the test silently stops asserting who claimed.
    function hashTx(bytes calldata btcTx) external pure returns (bytes32) {
        return BtcUtils.hashBtcTx(btcTx);
    }

    /// @notice The pegInId a claim of `btcTx` for `rskAddr` will be recorded under. The txid is
    /// hashed out of the transaction, mirroring what the contract does.
    function _pegInIdForTx(
        address rskAddr,
        bytes memory btcTx
    ) internal view returns (bytes32) {
        return _pegInId(rskAddr, this.hashTx(btcTx));
    }

    function _claimSlot(bytes32 pegInId) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(pegInId, PEGIN_CLAIMS_BASE_SLOT)));
    }

    function _readClaim(
        bytes32 pegInId
    )
        internal
        view
        returns (
            address claimerAddr,
            uint256 frontedAmount,
            uint256 feeAtClaim,
            uint256 requestBlock
        )
    {
        return _readClaimFrom(pegInContract, pegInId);
    }

    function _readClaimFrom(
        PegInContract target,
        bytes32 pegInId
    )
        internal
        view
        returns (
            address claimerAddr,
            uint256 frontedAmount,
            uint256 feeAtClaim,
            uint256 requestBlock
        )
    {
        uint256 base = _claimSlot(pegInId);
        claimerAddr = address(
            uint160(uint256(vm.load(address(target), bytes32(base))))
        );
        frontedAmount = uint256(vm.load(address(target), bytes32(base + 1)));
        feeAtClaim = uint256(vm.load(address(target), bytes32(base + 2)));
        requestBlock = uint256(vm.load(address(target), bytes32(base + 3)));
    }

    /// @notice Writes a claimer directly into a claim slot, to set up ordering fixtures
    function _seedClaim(
        PegInContract target,
        bytes32 pegInId,
        address claimerAddr
    ) internal {
        vm.store(
            address(target),
            bytes32(_claimSlot(pegInId)),
            bytes32(uint256(uint160(claimerAddr)))
        );
    }

    // ---- deposit-transaction fixtures ----
    //
    // requestPegIn no longer takes an amount or a txid: it reads both out of the raw deposit
    // transaction. So every call site needs a transaction that really pays the address derived
    // for its destination, built against the SAME inputs the contract derives with — this proxy's
    // address and the bridge mock's powpeg script. A test that wants a bad claim builds a bad
    // transaction; it can no longer just pass a bad number.

    /// @notice The P2SH scriptPubkey a deposit for `rskAddr` must pay, derived exactly as
    /// PegInContract derives it.
    function _depositPkScript(
        address rskAddr
    ) internal view returns (bytes memory) {
        return
            PegInDerivation.depositPkScript(
                rskAddr,
                address(pegInContract),
                bridgeMock.getActivePowpegRedeemScript()
            );
    }

    /// @notice A one-input, one-output raw transaction paying `pkScript` `valueSats` satoshis.
    /// @param nonce Mixed into the input outpoint so otherwise identical deposits get distinct
    /// txids, and therefore distinct pegInIds.
    function _buildTx(
        bytes memory pkScript,
        uint64 valueSats,
        uint256 nonce
    ) internal pure returns (bytes memory) {
        bytes memory valueLe = new bytes(8);
        uint64 v = valueSats;
        for (uint256 i = 0; i < 8; ++i) {
            valueLe[i] = bytes1(uint8(v & 0xFF));
            v >>= 8;
        }
        return
            abi.encodePacked(
                hex"01000000", // version
                hex"01", // input count
                bytes32(nonce), // prevout txid
                hex"00000000", // prevout index
                hex"00", // empty scriptSig
                hex"ffffffff", // sequence
                hex"01", // output count
                valueLe,
                bytes1(uint8(pkScript.length)),
                pkScript,
                hex"00000000" // locktime
            );
    }

    /// @notice A deposit transaction paying `rskAddr`'s derived address `amount` wei worth of BTC.
    function _depositTx(
        address rskAddr,
        uint256 amount,
        uint256 nonce
    ) internal view returns (bytes memory) {
        return _buildTx(_depositPkScript(rskAddr), _toSats(amount), nonce);
    }

    function _depositTx(
        address rskAddr,
        uint256 amount
    ) internal view returns (bytes memory) {
        return _depositTx(rskAddr, amount, DEFAULT_TX_NONCE);
    }

    /// @notice The default deposit fixture: DEFAULT_AMOUNT paid to rskUser's derived address.
    function _defaultTx() internal view returns (bytes memory) {
        return _depositTx(rskUser, DEFAULT_AMOUNT);
    }

    /// @notice A confirmed transaction that pays no address this protocol derives — the
    /// "any confirmed txid" an attacker would reach for.
    function _unrelatedTx() internal pure returns (bytes memory) {
        // Plain P2PKH to an arbitrary hash160, 1 BTC.
        bytes memory pkScript = abi.encodePacked(
            hex"76a914",
            bytes20(uint160(0xDEADBEEF)),
            hex"88ac"
        );
        return _buildTx(pkScript, 100_000_000, 7);
    }

    function _toSats(uint256 amountWei) internal pure returns (uint64) {
        require(
            amountWei % Quotes.SAT_TO_WEI_CONVERSION == 0,
            "fixture amount is not a whole number of satoshis"
        );
        return uint64(amountWei / Quotes.SAT_TO_WEI_CONVERSION);
    }

    // ---- call helpers ----

    function _emptyBranch() internal pure returns (bytes32[] memory) {
        return new bytes32[](0);
    }

    /// @notice Claims `btcTx`, which must already pay the address derived for `rskAddr`.
    function _requestPegInTx(
        address caller,
        address rskAddr,
        bytes memory btcTx,
        uint256 value
    ) internal returns (bytes32) {
        vm.prank(caller);
        return
            pegInContract.requestPegIn{value: value}(
                rskAddr,
                btcTx,
                "",
                bytes32(0),
                0,
                _emptyBranch()
            );
    }

    /// @notice Builds the deposit fixture for `amount` and claims it.
    function _requestPegIn(
        address caller,
        address rskAddr,
        uint256 amount,
        uint256 value
    ) internal returns (bytes32) {
        return
            _requestPegInTx(
                caller,
                rskAddr,
                _depositTx(rskAddr, amount),
                value
            );
    }

    function _expectedFee(uint256 amount) internal pure returns (uint256) {
        return
            DEFAULT_FIXED_FEE +
            (amount * DEFAULT_PERCENTAGE_FEE) /
            BASIS_POINTS;
    }
}
