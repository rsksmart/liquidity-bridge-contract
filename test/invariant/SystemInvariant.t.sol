// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {PegOutContract} from "../../src/PegOutContract.sol";
import {PegInContract} from "../../src/PegInContract.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {FlyoverDiscovery} from "../../src/FlyoverDiscovery.sol";
import {PauseRegistry} from "../../src/PauseRegistry.sol";
import {BridgeMock} from "../../src/test-contracts/BridgeMock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IPauseRegistry} from "../../src/interfaces/IPauseRegistry.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";
import {SystemHandler} from "./handlers/SystemHandler.sol";

/// @title System-Level Invariant Tests
/// @notice Tests cross-contract invariants for the full Flyover system
contract SystemInvariantTest is Test {
    PauseRegistry public pauseRegistry;
    CollateralManagementContract public collateralManagement;
    FlyoverDiscovery public discovery;
    PegInContract public pegInContract;
    PegOutContract public pegOutContract;
    BridgeMock public bridgeMock;
    SystemHandler public handler;

    address public owner;
    address public adder;
    address public slasher;
    address public user;
    address public punisher;

    uint48 constant ADMIN_DELAY = 30;
    uint256 constant MIN_COLLATERAL = 0.6 ether;
    uint256 constant RESIGN_DELAY = 500;
    uint256 constant REWARD_PERCENTAGE = 1000;
    uint256 constant DUST_THRESHOLD = 0.0000001 ether;
    uint256 constant BTC_BLOCK_TIME = 3600;
    uint256 constant MIN_PEGIN = 0.5 ether;
    uint256 constant PEGIN_DUST = 2300 * 65164000;

    function setUp() public {
        owner = makeAddr("owner");
        adder = makeAddr("adder");
        slasher = makeAddr("slasher");
        user = makeAddr("user");
        punisher = makeAddr("punisher");
        vm.deal(owner, 100 ether);
        vm.deal(adder, 1000 ether);
        vm.deal(user, 100 ether);

        _deployPauseRegistry();
        _deployCollateralManagement();
        _deployDiscovery();
        _deployPegIn();
        _deployPegOut();
        _grantRoles();

        handler = new SystemHandler(
            pegOutContract,
            pegInContract,
            collateralManagement,
            discovery,
            adder,
            slasher,
            user,
            punisher
        );

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](14);
        selectors[0] = handler.registerProvider.selector;
        selectors[1] = handler.addMoreCollateral.selector;
        selectors[2] = handler.pegInDeposit.selector;
        selectors[3] = handler.pegInWithdraw.selector;
        selectors[4] = handler.pegOutDeposit.selector;
        selectors[5] = handler.refundUserPegOut.selector;
        selectors[6] = handler.pegOutWithdraw.selector;
        selectors[7] = handler.resign.selector;
        selectors[8] = handler.withdrawCollateral.selector;
        selectors[9] = handler.setProviderStatus.selector;
        selectors[10] = handler.slashPegIn.selector;
        selectors[11] = handler.slashPegOut.selector;
        selectors[12] = handler.withdrawRewards.selector;
        selectors[13] = handler.advanceTime.selector;
        targetSelector(
            FuzzSelector({addr: address(handler), selectors: selectors})
        );
    }

    // ============ Invariant Tests ============

    /// @notice CollateralManagement balance must cover all collateral + rewards + penalties
    function invariant_CollateralSolvency() public view {
        uint256 balance = address(collateralManagement).balance;
        uint256 totalCollateral = 0;
        uint256 count = handler.getProviderCount();

        for (uint256 i = 0; i < count; i++) {
            address addr = handler.getProviderAddr(i);
            totalCollateral += collateralManagement.getPegInCollateral(addr);
            totalCollateral += collateralManagement.getPegOutCollateral(addr);
        }

        uint256 punisherRewards = collateralManagement.getRewards(punisher);
        uint256 userRewards = collateralManagement.getRewards(user);
        uint256 penalties = collateralManagement.getPenalties();

        assertGe(
            balance,
            totalCollateral + punisherRewards + userRewards + penalties,
            "INVARIANT VIOLATED: Collateral contract insolvent"
        );
    }

    /// @notice PegInContract balance must cover sum of all LP balances
    function invariant_PegInSolvency() public view {
        uint256 totalLPBalances = 0;
        uint256 count = handler.getProviderCount();

        for (uint256 i = 0; i < count; i++) {
            address addr = handler.getProviderAddr(i);
            totalLPBalances += pegInContract.getBalance(addr);
        }

        assertGe(
            address(pegInContract).balance,
            totalLPBalances,
            "INVARIANT VIOLATED: PegIn contract insolvent"
        );
    }

    /// @notice Discovery contract should never hold RBTC
    function invariant_DiscoveryHoldsNoRBTC() public view {
        assertEq(
            address(discovery).balance,
            0,
            "INVARIANT VIOLATED: Discovery holds RBTC"
        );
    }

    /// @notice isOperational consistency for all tracked providers
    function invariant_OperationalConsistency() public view {
        uint256 count = handler.getProviderCount();
        for (uint256 i = 0; i < count; i++) {
            address addr = handler.getProviderAddr(i);
            Flyover.ProviderType pType = handler.getProviderType(i);

            bool sufficient = collateralManagement.isCollateralSufficient(
                pType,
                addr
            );
            bool operational;

            // isOperational reverts for unregistered providers, so wrap in try
            try discovery.isOperational(pType, addr) returns (bool result) {
                operational = result;
            } catch {
                continue;
            }

            Flyover.LiquidityProvider memory lp;
            try discovery.getProvider(addr) returns (
                Flyover.LiquidityProvider memory result
            ) {
                lp = result;
            } catch {
                continue;
            }

            assertEq(
                operational,
                lp.status && sufficient,
                "INVARIANT VIOLATED: isOperational mismatch"
            );
        }
    }

    /// @notice Resigned providers must not be operational
    function invariant_ResignedNotOperational() public view {
        uint256 count = handler.getProviderCount();
        for (uint256 i = 0; i < count; i++) {
            if (!handler.isProviderResigned(i)) continue;

            address addr = handler.getProviderAddr(i);
            Flyover.ProviderType pType = handler.getProviderType(i);

            bool operational;
            try discovery.isOperational(pType, addr) returns (bool result) {
                operational = result;
            } catch {
                continue;
            }

            assertFalse(
                operational,
                "INVARIANT VIOLATED: Resigned provider is operational"
            );
        }
    }

    /// @notice No individual value should exceed the total RBTC injected into the system
    function invariant_NoUnderflowAnywhere() public view {
        uint256 totalRBTCIn = handler.ghost_totalRBTCIn();
        uint256 count = handler.getProviderCount();
        for (uint256 i = 0; i < count; i++) {
            address addr = handler.getProviderAddr(i);
            assertLe(
                collateralManagement.getPegInCollateral(addr),
                totalRBTCIn,
                "PegIn collateral exceeds total RBTC in"
            );
            assertLe(
                collateralManagement.getPegOutCollateral(addr),
                totalRBTCIn,
                "PegOut collateral exceeds total RBTC in"
            );
            assertLe(
                pegInContract.getBalance(addr),
                totalRBTCIn,
                "PegIn balance exceeds total RBTC in"
            );
            assertLe(
                pegOutContract.getBalance(addr),
                totalRBTCIn,
                "PegOut balance exceeds total RBTC in"
            );
        }
        assertLe(
            address(collateralManagement).balance,
            totalRBTCIn,
            "CM balance exceeds total RBTC in"
        );
        assertLe(
            address(pegInContract).balance,
            totalRBTCIn,
            "PegIn contract balance exceeds total RBTC in"
        );
        assertLe(
            address(pegOutContract).balance,
            totalRBTCIn,
            "PegOut contract balance exceeds total RBTC in"
        );
    }

    /// @notice Total RBTC across all contracts should not exceed total RBTC injected
    function invariant_GlobalConservation() public view {
        uint256 totalRBTCIn = handler.ghost_totalRBTCIn();
        if (totalRBTCIn == 0) return;

        uint256 systemBalance = address(collateralManagement).balance +
            address(pegInContract).balance +
            address(pegOutContract).balance +
            address(discovery).balance;

        assertLe(
            systemBalance,
            totalRBTCIn,
            "INVARIANT VIOLATED: System has more RBTC than was injected"
        );
    }

    /// @notice Rewards + penalties must equal total slashed across the system
    function invariant_SlashConservation() public view {
        uint256 slashed = handler.ghost_totalSlashed();
        if (slashed == 0) return;

        uint256 punisherRewards = collateralManagement.getRewards(punisher);
        uint256 userRewards = collateralManagement.getRewards(user);
        uint256 withdrawnRewards = handler.ghost_totalRewardsWithdrawn();
        uint256 penalties = collateralManagement.getPenalties();

        assertEq(
            punisherRewards + userRewards + withdrawnRewards + penalties,
            slashed,
            "INVARIANT VIOLATED: Rewards + penalties != total slashed"
        );
    }

    function invariant_callSummary() public view {
        console.log("\n--- System Invariant Summary ---");
        console.log("Providers:", handler.getProviderCount());
        console.log("Active pegout quotes:", handler.getActiveQuoteCount());
        console.log("Collateral added:", handler.ghost_totalCollateralAdded());
        console.log("PegIn deposited:", handler.ghost_totalPegInDeposited());
        console.log("PegOut deposited:", handler.ghost_totalPegOutDeposited());
        console.log("PegOut refunded:", handler.ghost_totalPegOutRefunded());
        console.log("Total slashed:", handler.ghost_totalSlashed());
        console.log(
            "Rewards withdrawn:",
            handler.ghost_totalRewardsWithdrawn()
        );
        console.log(
            "Collateral withdrawn:",
            handler.ghost_totalCollateralWithdrawn()
        );
        console.log("Total RBTC in:", handler.ghost_totalRBTCIn());
        console.log("CM balance:", address(collateralManagement).balance);
        console.log("PegIn balance:", address(pegInContract).balance);
        console.log("PegOut balance:", address(pegOutContract).balance);
        console.log("Discovery balance:", address(discovery).balance);
        console.log("--------------------------------\n");
    }

    // ============ Deployment Helpers ============

    function _deployPauseRegistry() internal {
        PauseRegistry impl = new PauseRegistry();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(impl.initialize, (0, owner))
        );
        pauseRegistry = PauseRegistry(payable(address(proxy)));
    }

    function _deployCollateralManagement() internal {
        CollateralManagementContract impl = new CollateralManagementContract();
        bytes memory initData = abi.encodeCall(
            impl.initialize,
            (
                owner,
                ADMIN_DELAY,
                MIN_COLLATERAL,
                RESIGN_DELAY,
                REWARD_PERCENTAGE,
                pauseRegistry
            )
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        collateralManagement = CollateralManagementContract(
            payable(address(proxy))
        );
    }

    function _deployDiscovery() internal {
        FlyoverDiscovery impl = new FlyoverDiscovery();
        bytes memory initData = abi.encodeCall(
            impl.initialize,
            (owner, uint48(5000), address(collateralManagement), pauseRegistry)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        discovery = FlyoverDiscovery(payable(address(proxy)));
    }

    function _deployPegIn() internal {
        bridgeMock = new BridgeMock();
        PegInContract impl = new PegInContract();
        bytes memory initData = abi.encodeCall(
            impl.initialize,
            (
                owner,
                payable(address(bridgeMock)),
                PEGIN_DUST,
                MIN_PEGIN,
                address(collateralManagement),
                false,
                pauseRegistry
            )
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        pegInContract = PegInContract(payable(address(proxy)));
    }

    function _deployPegOut() internal {
        PegOutContract impl = new PegOutContract();
        bytes memory initData = abi.encodeCall(
            impl.initialize,
            (
                owner,
                payable(address(bridgeMock)),
                DUST_THRESHOLD,
                address(collateralManagement),
                false,
                BTC_BLOCK_TIME,
                pauseRegistry
            )
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        pegOutContract = PegOutContract(payable(address(proxy)));
    }

    function _grantRoles() internal {
        vm.startPrank(owner);
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_ADDER(),
            address(discovery)
        );
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_ADDER(),
            adder
        );
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_SLASHER(),
            address(pegInContract)
        );
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_SLASHER(),
            address(pegOutContract)
        );
        collateralManagement.grantRole(
            collateralManagement.COLLATERAL_SLASHER(),
            slasher
        );
        vm.stopPrank();
    }
}
