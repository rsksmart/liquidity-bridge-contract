// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PegInContract} from "../../src/PegInContract.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {PauseRegistry} from "../../src/PauseRegistry.sol";
import {PegInAddressRegistry} from "../../src/PegInAddressRegistry.sol";
import {FlyoverConfigurations} from "../../src/FlyoverConfigurations.sol";
import {IFlyoverConfigurations} from "../../src/interfaces/IFlyoverConfigurations.sol";
import {E4BridgeMock} from "./E4BridgeMock.sol";

/// @title E4TestBase
/// @notice Shared setup for the E4 commit-first peg-in claim-flow suite. Deploys PegInContract,
/// CollateralManagement (with the global-slash machinery), FlyoverConfigurations (fees + tiers) and
/// the real PegInAddressRegistry (the derived-address source of truth), all behind ERC1967 proxies and
/// wired against a single E4BridgeMock that serves both the registry and the settlement path.
abstract contract E4TestBase is Test {
    bytes internal constant DERIVATION_DOMAIN = "FLYOVER_PEGIN_V1";
    uint256 internal constant SAT = 10 ** 10;

    uint48 internal constant ADMIN_DELAY = 0;
    uint256 internal constant TIMELOCK_DELAY = 1 days;
    uint256 internal constant MIN_COLLATERAL = 0.6 ether;
    uint256 internal constant RESIGN_DELAY_BLOCKS = 500;
    uint256 internal constant REWARD_PERCENTAGE = 1000;
    uint256 internal constant DUST_THRESHOLD = 2300 * 65164000;
    uint256 internal constant MIN_PEGIN = 0.5 ether;
    uint256 internal constant REGISTRANT_FEE = 0.001 ether;
    uint256 internal constant CLAIM_DEADLINE_BLOCKS = 100;

    address internal owner = makeAddr("owner");
    address internal lp = makeAddr("lp");
    address internal otherLp = makeAddr("otherLp");
    address internal registrant = makeAddr("registrant");
    address internal user = makeAddr("user");

    PauseRegistry internal pauseRegistry;
    CollateralManagementContract internal collateral;
    PegInContract internal pegIn;
    PegInAddressRegistry internal registry;
    FlyoverConfigurations internal config;
    E4BridgeMock internal bridge;

    function _deployAll() internal {
        vm.deal(owner, 100 ether);
        vm.deal(lp, 100 ether);
        vm.deal(otherLp, 100 ether);

        bridge = new E4BridgeMock();

        _deployPauseRegistry();
        _deployCollateral();
        _deployConfig();
        _deployRegistry();
        _deployPegIn();

        // Read role hashes outside any prank (these are contract calls and would otherwise consume it).
        bytes32 slasherRole = collateral.COLLATERAL_SLASHER();
        bytes32 adderRole = collateral.COLLATERAL_ADDER();

        vm.startPrank(owner);
        // Wire the claim-flow dependencies (registry + configurations + deadline + registrant fee).
        pegIn.setPegInClaimDependencies(address(registry), address(config), CLAIM_DEADLINE_BLOCKS, REGISTRANT_FEE);
        // Wire the PegInContract (lbcAddress) into the registry's derivation, so the deposit address
        // the registry derives is the SAME plain-P2SH the bridge re-derives at settlement (EB.1).
        registry.setPegInContract(address(pegIn));
        // Grant the slasher role to PegInContract so it can call globalSlash.
        collateral.grantRole(slasherRole, address(pegIn));
        // Seed two LPs with collateral so global slashing has eligible (past-grace) collateral.
        collateral.grantRole(adderRole, owner);
        collateral.addPegInCollateralTo{value: 5 ether}(lp);
        collateral.addPegInCollateralTo{value: 5 ether}(otherLp);
        vm.stopPrank();
    }

    function _deployPauseRegistry() private {
        PauseRegistry impl = new PauseRegistry();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), abi.encodeCall(impl.initialize, (0, owner)));
        pauseRegistry = PauseRegistry(payable(address(proxy)));
    }

    function _deployCollateral() private {
        CollateralManagementContract impl = new CollateralManagementContract();
        bytes memory initData = abi.encodeCall(
            CollateralManagementContract.initialize,
            (owner, ADMIN_DELAY, MIN_COLLATERAL, RESIGN_DELAY_BLOCKS, REWARD_PERCENTAGE, pauseRegistry)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        collateral = CollateralManagementContract(payable(address(proxy)));
    }

    function _deployConfig() private {
        FlyoverConfigurations impl = new FlyoverConfigurations();
        (
            IFlyoverConfigurations.PegConfiguration memory pegInCfg,
            IFlyoverConfigurations.PegConfiguration memory pegOutCfg
        ) = _seedConfigs();
        (
            IFlyoverConfigurations.PegConfiguration memory min,
            IFlyoverConfigurations.PegConfiguration memory max
        ) = _bounds();
        bytes memory initData = abi.encodeCall(
            FlyoverConfigurations.initialize,
            (owner, ADMIN_DELAY, TIMELOCK_DELAY, pegInCfg, pegOutCfg, min, max, min, max)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        config = FlyoverConfigurations(payable(address(proxy)));
    }

    function _deployRegistry() private {
        PegInAddressRegistry impl = new PegInAddressRegistry();
        bytes memory initData = abi.encodeCall(
            PegInAddressRegistry.initialize,
            (owner, ADMIN_DELAY, address(bridge), false)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        registry = PegInAddressRegistry(payable(address(proxy)));
    }

    function _deployPegIn() private {
        PegInContract impl = new PegInContract();
        bytes memory initData = abi.encodeCall(
            PegInContract.initialize,
            (owner, payable(address(bridge)), DUST_THRESHOLD, MIN_PEGIN, address(collateral), false, pauseRegistry)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        pegIn = PegInContract(payable(address(proxy)));
    }

    // ---- fixtures ----------------------------------------------------------

    function _derivationValue(address addr) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(DERIVATION_DOMAIN, addr));
    }

    /// @notice The config-sourced peg-in fee for an amount.
    function _fee(uint256 amount) internal view returns (uint256) {
        return config.calculatePegInFee(amount);
    }

    /// @notice An empty merkle-branch array for the SPV-proof claim args. The E4BridgeMock reads the
    /// confirmation count from setConfirmations and ignores the proof contents, so a dummy block hash
    /// (bytes32(0)), path (0) and empty branch exercise the proof-based gate without a real Merkle path.
    function _noBranches() internal pure returns (bytes32[] memory) {
        return new bytes32[](0);
    }

    /// @notice Builds the 25-byte P2SH scriptPubkey (OP_HASH160 <hash160> OP_EQUAL) of the address
    /// the registry derives for `addr`. The derived address is versionByte || hash160(20) || checksum(4).
    function _derivedScriptPubkey(address addr) internal view returns (bytes memory) {
        (bytes memory a, ) = registry.getPegInAddress(addr);
        require(a.length == 25, "unexpected derived address length");
        bytes20 hash160;
        assembly {
            hash160 := mload(add(a, 33))
        }
        return bytes.concat(hex"a914", hash160, hex"87");
    }

    /// @notice Builds a minimal serialized BTC tx (single P2SH output) paying the derived address.
    function _btcTxForAddr(address addr) internal view returns (bytes memory) {
        bytes memory scriptPubkey = _derivedScriptPubkey(addr);
        return bytes.concat(
            hex"02000000", hex"01", bytes32(0), hex"00000000", hex"00", hex"ffffffff",
            hex"01", hex"00ca9a3b00000000", bytes1(uint8(scriptPubkey.length)), scriptPubkey,
            hex"00000000"
        );
    }

    /// @notice Registers `addr` in the registry by proving a BTC deposit to its derived address. The
    /// deposit is left funded in the bridge mock so a later resolvePegIn can settle it.
    function _register(address addr, uint256 amount) internal {
        vm.deal(address(this), address(this).balance + amount);
        bridge.fund{value: amount}(_derivationValue(addr));
        bytes32[] memory branches;
        registry.registerAddress(addr, _btcTxForAddr(addr), bytes32(0), 0, branches);
    }

    /// @notice Builds an OP_RETURN SC-call payload: destContract(20) || maxGasFee(32) || callData.
    function _opReturn(address destination, uint256 maxGasFee, bytes memory callData)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(bytes20(destination), bytes32(maxGasFee), callData);
    }

    function _seedConfigs()
        internal
        pure
        returns (
            IFlyoverConfigurations.PegConfiguration memory pegInCfg,
            IFlyoverConfigurations.PegConfiguration memory pegOutCfg
        )
    {
        pegInCfg = _baseConfig();
        pegInCfg.fixedFee = 1000 * SAT; // 1e13 wei, satoshi-aligned
        pegInCfg.percentageFee = 10;    // 0.1%
        pegInCfg.confirmationTiers = new IFlyoverConfigurations.ConfirmationTier[](3);
        pegInCfg.confirmationTiers[0] = IFlyoverConfigurations.ConfirmationTier({maxAmount: 1 ether, confirmations: 2});
        pegInCfg.confirmationTiers[1] = IFlyoverConfigurations.ConfirmationTier({maxAmount: 10 ether, confirmations: 6});
        pegInCfg.confirmationTiers[2] = IFlyoverConfigurations.ConfirmationTier({maxAmount: 100 ether, confirmations: 20});

        pegOutCfg = _baseConfig();
        pegOutCfg.fixedFee = 2000 * SAT;
        pegOutCfg.percentageFee = 20;
        pegOutCfg.confirmationTiers = new IFlyoverConfigurations.ConfirmationTier[](1);
        pegOutCfg.confirmationTiers[0] = IFlyoverConfigurations.ConfirmationTier({maxAmount: 50 ether, confirmations: 4});
    }

    function _baseConfig() internal pure returns (IFlyoverConfigurations.PegConfiguration memory c) {
        c.fixedFee = 1000 * SAT;
        c.percentageFee = 10;
        c.penaltyFee = 0.01 ether;
        c.callTime = 2 hours;
        c.expireTime = 2 hours + 30 minutes;
        c.expireBlocks = 500;
        c.deliveryGrace = 60;
        c.minAmount = 0.001 ether;
        c.maxAmount = 100 ether;
    }

    function _bounds()
        internal
        pure
        returns (
            IFlyoverConfigurations.PegConfiguration memory min,
            IFlyoverConfigurations.PegConfiguration memory max
        )
    {
        max.fixedFee = 1 ether;
        max.percentageFee = 1_000;
        max.penaltyFee = 10 ether;
        max.callTime = 7 days;
        max.expireTime = 8 days;
        max.expireBlocks = 1_000_000;
        max.deliveryGrace = 1 days;
        max.minAmount = 1 ether;
        max.maxAmount = 10_000 ether;
    }
}
