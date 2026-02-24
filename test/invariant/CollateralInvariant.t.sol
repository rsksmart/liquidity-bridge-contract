// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PauseRegistry} from "../../src/PauseRegistry.sol";
import {IPauseRegistry} from "../../src/interfaces/IPauseRegistry.sol";

/// @title CollateralManagement Invariant Tests
/// @notice Tests critical invariants for the CollateralManagement contract
contract CollateralInvariantTest is Test {
    CollateralManagementContract public collateralManagement;

    address public owner;
    address public adder;
    address public slasher;
    address public punisher;

    // Track providers for invariant checks
    address[] public providers;

    // Ghost variables
    uint256 public ghost_totalAdded;
    uint256 public ghost_totalSlashed;
    uint256 public ghost_totalWithdrawn;

    uint256 constant MIN_COLLATERAL = 0.6 ether;
    uint256 constant RESIGN_DELAY = 500;
    uint256 constant REWARD_PERCENTAGE = 1000;

    function setUp() public {
        owner = makeAddr("owner");
        adder = makeAddr("adder");
        slasher = makeAddr("slasher");
        punisher = makeAddr("punisher");

        vm.deal(owner, 100 ether);
        vm.deal(adder, 100 ether);

        // Deploy PauseRegistry first
        PauseRegistry prImpl = new PauseRegistry();
        ERC1967Proxy prProxy = new ERC1967Proxy(
            address(prImpl),
            abi.encodeCall(prImpl.initialize, (0, owner))
        );
        IPauseRegistry pauseRegistry = IPauseRegistry(
            payable(address(prProxy))
        );

        // Deploy CollateralManagement
        CollateralManagementContract impl = new CollateralManagementContract();
        bytes memory initData = abi.encodeCall(
            CollateralManagementContract.initialize,
            (
                owner,
                30,
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

        // Grant roles
        bytes32 adderRole = collateralManagement.COLLATERAL_ADDER();
        bytes32 slasherRole = collateralManagement.COLLATERAL_SLASHER();

        vm.startPrank(owner);
        collateralManagement.grantRole(adderRole, adder);
        collateralManagement.grantRole(slasherRole, slasher);
        vm.stopPrank();

        // Target this contract for invariant testing
        targetContract(address(this));

        // Exclude setUp from being called during invariant testing
        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = this.addCollateral.selector;
        selectors[1] = this.resignAndWithdraw.selector;
        targetSelector(
            FuzzSelector({addr: address(this), selectors: selectors})
        );
    }

    // ============ Handler Functions ============

    function addCollateral(uint256 providerSeed, uint256 amount) external {
        amount = bound(amount, MIN_COLLATERAL, 10 ether);
        address provider = _getOrCreateProvider(providerSeed);

        vm.deal(adder, amount);
        vm.prank(adder);
        collateralManagement.addPegInCollateralTo{value: amount}(provider);

        ghost_totalAdded += amount;
    }

    function resignAndWithdraw(uint256 providerSeed) external {
        if (providers.length == 0) return;

        address provider = providers[providerSeed % providers.length];
        uint256 pegInCollateral = collateralManagement.getPegInCollateral(
            provider
        );

        if (pegInCollateral == 0) return;

        // Resign first
        vm.prank(provider);
        try collateralManagement.resign() {} catch {
            return;
        }

        // Advance blocks past delay
        vm.roll(block.number + RESIGN_DELAY + 1);

        // Withdraw
        vm.prank(provider);
        try collateralManagement.withdrawCollateral() {
            ghost_totalWithdrawn += pegInCollateral;
        } catch {}
    }

    // ============ Invariant Tests ============

    /// @notice Contract balance should always be >= total collateral obligations
    function invariant_ContractSolvent() public view {
        uint256 contractBalance = address(collateralManagement).balance;
        uint256 totalCollateral = _calculateTotalCollateral();

        assertGe(
            contractBalance,
            totalCollateral,
            "INVARIANT VIOLATED: Contract is insolvent"
        );
    }

    /// @notice Ghost accounting should match contract state (relaxed check)
    function invariant_GhostAccountingConsistent() public view {
        // If nothing has been added via our handlers, skip this check
        if (ghost_totalAdded == 0) return;

        uint256 contractBalance = address(collateralManagement).balance;

        // Contract balance should be reasonable - not more than we added
        assertTrue(
            contractBalance <= ghost_totalAdded + 1 ether,
            "INVARIANT VIOLATED: Contract has more than deposited"
        );
    }

    /// @notice No provider should have negative collateral (underflow)
    function invariant_NoNegativeCollateral() public view {
        for (uint256 i = 0; i < providers.length; i++) {
            uint256 pegInCollateral = collateralManagement.getPegInCollateral(
                providers[i]
            );
            uint256 pegOutCollateral = collateralManagement.getPegOutCollateral(
                providers[i]
            );

            // Check for underflow - values near max uint256 indicate underflow
            assertTrue(
                pegInCollateral < 1_000_000 ether,
                "INVARIANT VIOLATED: PegIn collateral underflowed"
            );
            assertTrue(
                pegOutCollateral < 1_000_000 ether,
                "INVARIANT VIOLATED: PegOut collateral underflowed"
            );
        }
    }

    // ============ Helper Functions ============

    function _getOrCreateProvider(
        uint256 seed
    ) internal returns (address provider) {
        if (providers.length > 0 && seed % 3 != 0) {
            return providers[seed % providers.length];
        }

        provider = address(
            uint160(uint256(keccak256(abi.encode(seed, providers.length))))
        );
        providers.push(provider);
        vm.deal(provider, 10 ether);
        return provider;
    }

    function _calculateTotalCollateral() internal view returns (uint256 total) {
        for (uint256 i = 0; i < providers.length; i++) {
            uint256 pegInCollateral = collateralManagement.getPegInCollateral(
                providers[i]
            );
            uint256 pegOutCollateral = collateralManagement.getPegOutCollateral(
                providers[i]
            );
            total += pegInCollateral + pegOutCollateral;
        }
    }

    function invariant_callSummary() public view {
        console.log("\n--- Collateral Invariant Summary ---");
        console.log("Providers:", providers.length);
        console.log("Total added:", ghost_totalAdded);
        console.log("Total slashed:", ghost_totalSlashed);
        console.log("Total withdrawn:", ghost_totalWithdrawn);
        console.log("Contract balance:", address(collateralManagement).balance);
        console.log("------------------------------------\n");
    }
}
