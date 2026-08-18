// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PegInTestBase} from "./PegInTestBase.sol";
import {FlyoverConfigurationsMock} from "./FlyoverConfigurationsMock.sol";
import {PegInContract} from "../../src/PegInContract.sol";
import {PegInAddressRegistryHarness} from "../pegin-registry/PegInAddressRegistryHarness.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

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

    bytes32 internal constant DEFAULT_BTC_TX_HASH = keccak256("default-btc-tx");
    uint256 internal constant DEFAULT_AMOUNT = 5 ether;

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
        configurations.setRegistrantFee(1e14);
        configurations.setAmountBounds(TEST_MIN_PEGIN, DEFAULT_MAX_AMOUNT);
        IFlyoverConfigurations.ConfirmationTier[]
            memory tiers = new IFlyoverConfigurations.ConfirmationTier[](1);
        tiers[0] = IFlyoverConfigurations.ConfirmationTier({
            maxAmount: type(uint256).max,
            confirmations: DEFAULT_TIER_CONFIRMATIONS
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

    // ---- call helpers ----

    function _emptyBranch() internal pure returns (bytes32[] memory) {
        return new bytes32[](0);
    }

    function _requestPegIn(
        address caller,
        address rskAddr,
        uint256 amount,
        bytes32 btcTxHash,
        uint256 value
    ) internal returns (bytes32) {
        vm.prank(caller);
        return
            pegInContract.requestPegIn{value: value}(
                rskAddr,
                amount,
                btcTxHash,
                "",
                bytes32(0),
                0,
                _emptyBranch()
            );
    }

    function _expectedFee(uint256 amount) internal pure returns (uint256) {
        return
            DEFAULT_FIXED_FEE +
            (amount * DEFAULT_PERCENTAGE_FEE) /
            BASIS_POINTS;
    }
}
