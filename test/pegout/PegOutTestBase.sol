// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {PegOutContract} from "../../src/PegOutContract.sol";
import {CollateralManagementContract} from "../../src/CollateralManagement.sol";
import {FlyoverDiscovery} from "../../src/FlyoverDiscovery.sol";
import {BridgeMock} from "../../src/test-contracts/BridgeMock.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Quotes} from "../../src/libraries/Quotes.sol";
import {Flyover} from "../../src/libraries/Flyover.sol";

/// @title Base contract for PegOut tests
/// @notice Provides shared deployment and setup logic for PegOut tests
abstract contract PegOutTestBase is Test {
    PegOutContract public pegOutContract;
    CollateralManagementContract public collateralManagement;
    FlyoverDiscovery public discovery;
    BridgeMock public bridgeMock;

    address public owner;
    address public pegInLp;
    address public pegOutLp;
    address public fullLp;

    // Private keys for signing (needed for signature validation tests)
    uint256 public pegInLpKey;
    uint256 public pegOutLpKey;
    uint256 public fullLpKey;

    // Test constants
    uint48 constant TEST_DEFAULT_ADMIN_DELAY = 30;
    uint256 constant TEST_MIN_COLLATERAL = 0.6 ether;
    uint256 constant TEST_RESIGN_DELAY_BLOCKS = 500;
    uint256 constant TEST_REWARD_PERCENTAGE = 1000;
    uint256 constant TEST_DUST_THRESHOLD = 0.0000001 ether; // From PEGOUT_CONSTANTS
    uint256 constant TEST_BTC_BLOCK_TIME = 3600;
    uint256 constant DISCOVERY_INITIAL_DELAY = 5000;
    uint256 constant MIN_COLLATERAL = 0.6 ether;

    address constant ZERO_ADDRESS = address(0);

    // BTC Mock Constants (shared across all PegOut tests)
    bytes32 constant BLOCK_HEADER_HASH = bytes32(uint256(1));
    uint256 constant PARTIAL_MERKLE_TREE = 0;
    bytes32[] internal merkleHashes;

    /// @notice Deploy PegOutContract with all dependencies
    function deployPegOutContract() internal {
        // Create owner
        owner = makeAddr("owner");
        vm.deal(owner, 100 ether);

        // Deploy CollateralManagement
        deployCollateralManagement();

        // Deploy Discovery
        deployDiscovery();

        // Deploy BridgeMock
        bridgeMock = new BridgeMock();

        // Deploy PegOutContract
        PegOutContract implementation = new PegOutContract();

        bytes memory initData = abi.encodeCall(
            PegOutContract.initialize,
            (
                owner,
                payable(address(bridgeMock)),
                TEST_DUST_THRESHOLD,
                address(collateralManagement),
                false, // mainnet
                TEST_BTC_BLOCK_TIME,
                0, // feePercentage
                payable(ZERO_ADDRESS) // feeCollector
            )
        );

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            initData
        );
        pegOutContract = PegOutContract(payable(address(proxy)));

        // Grant COLLATERAL_SLASHER role to PegOutContract
        // Store the role hash BEFORE prank to avoid consuming it
        bytes32 slasherRole = collateralManagement.COLLATERAL_SLASHER();

        vm.prank(owner);
        collateralManagement.grantRole(slasherRole, address(pegOutContract));
    }

    function deployCollateralManagement() internal {
        CollateralManagementContract cmImplementation = new CollateralManagementContract();

        bytes memory cmInitData = abi.encodeCall(
            CollateralManagementContract.initialize,
            (
                owner,
                TEST_DEFAULT_ADMIN_DELAY,
                TEST_MIN_COLLATERAL,
                TEST_RESIGN_DELAY_BLOCKS,
                TEST_REWARD_PERCENTAGE
            )
        );

        ERC1967Proxy cmProxy = new ERC1967Proxy(
            address(cmImplementation),
            cmInitData
        );
        collateralManagement = CollateralManagementContract(
            payable(address(cmProxy))
        );

        // Verify owner has admin role (should be automatic with delay = 0)
        require(
            collateralManagement.hasRole(
                collateralManagement.DEFAULT_ADMIN_ROLE(),
                owner
            ),
            "Owner should have DEFAULT_ADMIN_ROLE"
        );
    }

    function deployDiscovery() internal {
        FlyoverDiscovery discoveryImplementation = new FlyoverDiscovery();

        bytes memory discoveryInitData = abi.encodeCall(
            FlyoverDiscovery.initialize,
            (
                owner,
                uint48(DISCOVERY_INITIAL_DELAY),
                address(collateralManagement)
            )
        );

        ERC1967Proxy discoveryProxy = new ERC1967Proxy(
            address(discoveryImplementation),
            discoveryInitData
        );
        discovery = FlyoverDiscovery(payable(address(discoveryProxy)));

        // Grant COLLATERAL_ADDER role to Discovery contract
        // Store the role hash BEFORE prank to avoid consuming it
        bytes32 adderRole = collateralManagement.COLLATERAL_ADDER();

        vm.prank(owner);
        collateralManagement.grantRole(adderRole, address(discovery));
    }

    /// @notice Setup providers with collateral
    function setupProviders() internal {
        // Create addresses with known private keys for signature testing
        (pegInLp, pegInLpKey) = makeAddrAndKey("pegInLp");
        (pegOutLp, pegOutLpKey) = makeAddrAndKey("pegOutLp");
        (fullLp, fullLpKey) = makeAddrAndKey("fullLp");

        // Fund providers
        vm.deal(pegInLp, 100 ether);
        vm.deal(pegOutLp, 100 ether);
        vm.deal(fullLp, 100 ether);

        // Register providers via Discovery
        vm.prank(pegInLp);
        discovery.register{value: MIN_COLLATERAL}(
            "Pegin Provider",
            "lp1.com",
            true,
            Flyover.ProviderType.PegIn
        );

        vm.prank(pegOutLp);
        discovery.register{value: MIN_COLLATERAL}(
            "PegOut Provider",
            "lp2.com",
            true,
            Flyover.ProviderType.PegOut
        );

        vm.prank(fullLp);
        discovery.register{value: MIN_COLLATERAL * 2}(
            "Full Provider",
            "lp3.com",
            true,
            Flyover.ProviderType.Both
        );
    }

    /// @notice Initialize BTC mock data (call in setUp of test contracts)
    function initBtcMocks() internal {
        merkleHashes = new bytes32[](1);
        merkleHashes[0] = bytes32(uint256(1));
    }

    /// @notice Creates a BTC block header with a specific timestamp
    /// @param timestamp The Unix timestamp for the block
    /// @return header The 80-byte BTC block header
    function createBtcBlockHeader(
        uint32 timestamp
    ) internal pure returns (bytes memory) {
        bytes memory header = new bytes(80);

        // Place timestamp at offset 68 (little-endian)
        header[68] = bytes1(uint8(timestamp));
        header[69] = bytes1(uint8(timestamp >> 8));
        header[70] = bytes1(uint8(timestamp >> 16));
        header[71] = bytes1(uint8(timestamp >> 24));

        return header;
    }

    /// @notice Converts uint64 to 8-byte little-endian
    function toLittleEndian64(
        uint64 value
    ) internal pure returns (bytes memory) {
        bytes memory result = new bytes(8);
        result[0] = bytes1(uint8(value));
        result[1] = bytes1(uint8(value >> 8));
        result[2] = bytes1(uint8(value >> 16));
        result[3] = bytes1(uint8(value >> 24));
        result[4] = bytes1(uint8(value >> 32));
        result[5] = bytes1(uint8(value >> 40));
        result[6] = bytes1(uint8(value >> 48));
        result[7] = bytes1(uint8(value >> 56));
        return result;
    }

    /// @notice Generates a simple mock BTC transaction for testing
    /// @dev Creates a minimal valid BTC tx with P2PKH output (same as Hardhat tests)
    /// @param quote The PegOut quote
    /// @param quoteHash The hash of the quote
    /// @return btcTx The raw BTC transaction bytes
    function generateMockBtcTx(
        Quotes.PegOutQuote memory quote,
        bytes32 quoteHash
    ) internal pure returns (bytes memory) {
        // Convert quote value from WEI to SAT (divide by 10^10)
        uint64 satAmount = uint64(quote.value / 1e10);

        // Extract P2PKH hash160 from 21-byte address (skip version byte)
        bytes memory hash160 = new bytes(20);
        for (uint i = 0; i < 20; i++) {
            hash160[i] = quote.depositAddress[i + 1];
        }

        // Create P2PKH output script
        bytes memory outputScript = abi.encodePacked(
            hex"76a914", // OP_DUP OP_HASH160 PUSH20
            hash160,
            hex"88ac" // OP_EQUALVERIFY OP_CHECKSIG
        );

        // Build mock transaction (same structure as Hardhat tests)
        return
            abi.encodePacked(
                hex"01000000", // Version
                hex"01", // 1 input
                // Hardcoded previous tx and signature (same as Hardhat)
                hex"013503c427ba46058d2d8ac9221a2f6fd50734a69f19dae65420191e3ada2d40",
                hex"00000000",
                hex"6a",
                hex"47304402205d047dbd8c49aea5bd0400b85a57b2da7e139cec632fb138b7bee1d382fd70ca02201aa529f59b4f66fdf86b0728937a91a40962aedd3f6e30bce5208fec0464d54901210255507b238c6f14735a7abe96a635058da47b05b61737a610bef757f009eea2a4",
                hex"ffffffff",
                hex"02", // 2 outputs
                // Output 1: Payment to user
                toLittleEndian64(satAmount),
                uint8(outputScript.length),
                outputScript,
                // Output 2: OP_RETURN with quote hash
                hex"0000000000000000", // 0 amount
                hex"22", // script length (34 bytes)
                hex"6a20", // OP_RETURN PUSH32
                quoteHash,
                hex"00000000" // Locktime
            );
    }
}
